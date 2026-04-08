// app.go is the Wails application entry point.
//
// It wires together the Go backend with the React frontend by:
//   - Holding a reference to the discovery.Service.
//   - Exposing methods via Wails bindings so the frontend can call them
//     as if they were regular async JavaScript functions.
//
// All methods in this file are callable from the React frontend via:
//
//	import { GetPeers } from '../wailsjs/go/main/App'
package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"sync"

	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"

	"palt/internal/discovery"
	"palt/internal/models"
	"palt/internal/transfer"
)

// paltPort is the TCP port this instance advertises for file transfers.
// It will also be the port the transfer server binds to (Phase 2).
const paltPort = 9876

type OfferResolution struct {
	Accept   bool
	SavePath string
}

// App is the root Wails application struct.
// Every exported method on App becomes a Wails binding.
type App struct {
	ctx       context.Context
	discovery *discovery.Service

	transferServer *transfer.Server
	pendingOffers  map[string]chan OfferResolution
	offersMu       sync.Mutex
}

// NewApp constructs an App instance. Wails calls this during startup.
func NewApp() *App {
	return &App{
		pendingOffers: make(map[string]chan OfferResolution),
	}
}

// startup is called by Wails after the application window is ready.
// This is the correct place to initialise services that need a context.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "PALT Desktop"
	}

	// Detect the host OS so peers can show a platform icon.
	hostOS := runtime.GOOS // "linux", "darwin", "windows"

	svc, err := discovery.NewService(ctx, hostname, paltPort, hostOS)
	if err != nil {
		log.Fatalf("[app] Could not start discovery service: %v", err)
	}

	a.discovery = svc

	// Initialize Custom TCP Transfer Server
	a.transferServer = transfer.NewServer(paltPort)
	a.transferServer.OnOffer = func(meta transfer.Metadata) (bool, string) {
		offerChan := make(chan OfferResolution, 1)

		a.offersMu.Lock()
		a.pendingOffers[meta.TransferID] = offerChan
		a.offersMu.Unlock()

		// Tell React UI a device wants to send a file
		wailsruntime.EventsEmit(a.ctx, "transfer_offer", meta)

		// Wait indefinitely for user to click Accept or Reject in the UI
		res := <-offerChan

		a.offersMu.Lock()
		delete(a.pendingOffers, meta.TransferID)
		a.offersMu.Unlock()

		return res.Accept, res.SavePath
	}

	a.transferServer.OnProgress = func(transferID string, written int64, total int64) {
		wailsruntime.EventsEmit(a.ctx, "transfer_progress", map[string]interface{}{
			"transferId": transferID,
			"written":    written,
			"total":      total,
		})
	}

	if err := a.transferServer.Start(); err != nil {
		log.Fatalf("[app] Could not start transfer TCP server: %v", err)
	}

	log.Println("[app] PALT started successfully.")
}

// shutdown is called by Wails when the window is closed.
func (a *App) shutdown(ctx context.Context) {
	if a.discovery != nil {
		a.discovery.Stop()
	}
	if a.transferServer != nil {
		a.transferServer.Stop()
	}
}

// ─── Wails Bindings (callable from React) ────────────────────────────────────

// GetPeers returns the current list of discovered PALT peers on the LAN.
func (a *App) GetPeers() []models.Peer {
	if a.discovery == nil {
		return []models.Peer{}
	}
	return a.discovery.GetPeers()
}

// GetLocalDevice returns metadata about this device for display in the UI.
func (a *App) GetLocalDevice() models.Peer {
	hostname, _ := os.Hostname()
	return models.Peer{
		ID:         "local",
		DeviceName: hostname,
		IPAddress:  "127.0.0.1",
		Port:       paltPort,
		OS:         runtime.GOOS,
	}
}

// AcceptOffer is called by React when user clicks Accept.
// Opens the native Wails save dialog.
func (a *App) AcceptOffer(transferID string, defaultFileName string) {
	savePath, err := wailsruntime.SaveFileDialog(a.ctx, wailsruntime.SaveDialogOptions{
		Title:           "Save Incoming PALT File",
		DefaultFilename: defaultFileName,
	})

	a.offersMu.Lock()
	ch, ok := a.pendingOffers[transferID]
	a.offersMu.Unlock()

	if !ok {
		return
	}

	// Native dialog returns empty string on "Cancel"
	if err != nil || savePath == "" {
		ch <- OfferResolution{Accept: false}
		return
	}

	ch <- OfferResolution{Accept: true, SavePath: savePath}
}

// AutoAcceptOffer automatically accepts the file and directs it to ~/Downloads/PALT.
func (a *App) AutoAcceptOffer(transferID string, fileName string) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Printf("[app] AutoAcceptOffer error getting home dir: %v\n", err)
		a.RejectOffer(transferID)
		return
	}

	downloadDir := filepath.Join(homeDir, "Downloads", "PALT")
	err = os.MkdirAll(downloadDir, os.ModePerm)
	if err != nil {
		log.Printf("[app] AutoAcceptOffer error creating PALT download dir: %v\n", err)
		a.RejectOffer(transferID)
		return
	}

	savePath := filepath.Join(downloadDir, fileName)

	a.offersMu.Lock()
	ch, ok := a.pendingOffers[transferID]
	a.offersMu.Unlock()

	if !ok {
		return
	}

	ch <- OfferResolution{Accept: true, SavePath: savePath}
}

// RejectOffer is called by React when user clicks Reject (closes the modal).
func (a *App) RejectOffer(transferID string) {
	a.offersMu.Lock()
	ch, ok := a.pendingOffers[transferID]
	a.offersMu.Unlock()

	if ok {
		ch <- OfferResolution{Accept: false}
	}
}

// SendFile is called by React when clicking "Send File" on a PeerCard.
func (a *App) SendFile(peerIP string, peerPort int) error {
	log.Printf("[app] SendFile triggered for peer %s:%d\n", peerIP, peerPort)

	filePath, err := wailsruntime.OpenFileDialog(a.ctx, wailsruntime.OpenDialogOptions{
		Title: "Select File to Send via PALT",
	})
	
	if err != nil {
		log.Printf("[app] OpenFileDialog error: %v\n", err)
		return err
	}
	if filePath == "" {
		log.Printf("[app] OpenFileDialog cancelled by user\n")
		return nil
	}

	log.Printf("[app] User selected file: %s", filePath)

	transferID := generateTransferID()
	hostname, _ := os.Hostname()

	// Notify UI right away so it can pop up the progress bar
	wailsruntime.EventsEmit(a.ctx, "transfer_started", map[string]interface{}{
		"transferId": transferID,
		"fileName":   filepath.Base(filePath),
		"senderName": hostname,
		"direction":  "outgoing",
	})

	// Run network operation async
	go func() {
		err := transfer.SendFile(peerIP, peerPort, filePath, transferID, hostname, func(written, total int64) {
			wailsruntime.EventsEmit(a.ctx, "transfer_progress", map[string]interface{}{
				"transferId": transferID,
				"written":    written,
				"total":      total,
			})
		})

		if err != nil {
			log.Printf("[app] SendFile error: %v", err)
			wailsruntime.EventsEmit(a.ctx, "transfer_error", map[string]interface{}{
				"transferId": transferID,
				"error":      err.Error(),
			})
		} else {
			// Ensure it completes at 100% locally
			wailsruntime.EventsEmit(a.ctx, "transfer_complete", map[string]interface{}{
				"transferId": transferID,
			})
		}
	}()

	return nil
}

func generateTransferID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return fmt.Sprintf("%x-%x", b[0:4], b[4:8])
}
