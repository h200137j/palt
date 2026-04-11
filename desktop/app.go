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
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"

	"palt/internal/discovery"
	"palt/internal/models"
	"palt/internal/transfer"
)

// AppVersion is the canonical version string for this build.
// Bump this manually to match the git tag when cutting a release.
const AppVersion = "v1.0.8"

// UpdateInfo is returned by CheckForUpdate and passed to the React frontend.
type UpdateInfo struct {
	IsNewer       bool   `json:"isNewer"`
	LatestVersion string `json:"latestVersion"`
	DownloadURL   string `json:"downloadUrl"`
	ReleaseNotes  string `json:"releaseNotes"`
}

// paltPort is the TCP port this instance advertises for file transfers.
// It will also be the port the transfer server binds to (Phase 2).
const paltPort = 9876

type OfferResolution struct {
	Accept bool
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
	a.transferServer.OnOffer = func(meta transfer.Metadata) bool {
		offerChan := make(chan OfferResolution, 1)

		a.offersMu.Lock()
		a.pendingOffers[meta.TransferID] = offerChan
		a.offersMu.Unlock()

		// Tell React UI a device wants to send some files
		wailsruntime.EventsEmit(a.ctx, "transfer_offer", meta)

		// Wait indefinitely for user to click Accept or Reject in the UI
		res := <-offerChan

		a.offersMu.Lock()
		delete(a.pendingOffers, meta.TransferID)
		a.offersMu.Unlock()

		return res.Accept
	}

	a.transferServer.OnProgress = func(transferID string, written int64, total int64, sentItems int, totalItems int) {
		wailsruntime.EventsEmit(a.ctx, "transfer_progress", map[string]interface{}{
			"transferId": transferID,
			"written":    written,
			"total":      total,
			"sentItems":  sentItems,
			"totalItems": totalItems,
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

// GetAppVersion returns the build-time version constant.
func (a *App) GetAppVersion() string {
	return AppVersion
}

// CheckForUpdate queries the GitHub Releases API and compares the latest tag
// against AppVersion. Returns UpdateInfo with isNewer=false on any error so
// the UI degrades silently when offline.
func (a *App) CheckForUpdate() UpdateInfo {
	const apiURL = "https://api.github.com/repos/h200137j/palt/releases/latest"

	client := &http.Client{Timeout: 10 * 1e9} // 10 s
	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		log.Printf("[updater] Failed to build request: %v", err)
		return UpdateInfo{}
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "palt-desktop/"+AppVersion)

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[updater] HTTP request failed: %v", err)
		return UpdateInfo{}
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("[updater] Failed to read body: %v", err)
		return UpdateInfo{}
	}

	var release struct {
		TagName string `json:"tag_name"`
		Body    string `json:"body"`
		Assets  []struct {
			Name               string `json:"name"`
			BrowserDownloadURL string `json:"browser_download_url"`
		} `json:"assets"`
	}
	if err := json.Unmarshal(body, &release); err != nil {
		log.Printf("[updater] Failed to parse release JSON: %v", err)
		return UpdateInfo{}
	}

	latest := release.TagName
	isNewer := compareVersions(latest, AppVersion)

	if !isNewer {
		log.Printf("[updater] Up-to-date (%s)", AppVersion)
		return UpdateInfo{LatestVersion: latest}
	}

	// Find the .deb asset download URL.
	downloadURL := ""
	for _, asset := range release.Assets {
		if strings.HasSuffix(asset.Name, ".deb") {
			downloadURL = asset.BrowserDownloadURL
			break
		}
	}
	// Fall back to the releases page if no .deb is attached.
	if downloadURL == "" {
		downloadURL = "https://github.com/h200137j/palt/releases/latest"
	}

	log.Printf("[updater] Update available: %s → %s", AppVersion, latest)
	return UpdateInfo{
		IsNewer:       true,
		LatestVersion: latest,
		DownloadURL:   downloadURL,
		ReleaseNotes:  release.Body,
	}
}

// OpenURL opens a URL in the system's default browser.
func (a *App) OpenURL(url string) {
	wailsruntime.BrowserOpenURL(a.ctx, url)
}

// configDir returns (and creates if needed) the PALT config directory.
func configDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, ".config", "palt")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// GetLastSeenVersion reads the persisted last-seen version from disk.
// Returns an empty string if the file doesn't exist yet (first ever launch).
func (a *App) GetLastSeenVersion() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	data, err := os.ReadFile(filepath.Join(dir, "last_seen_version"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

// SaveLastSeenVersion persists the given version string so the changelog
// dialog is only shown once per new version.
func (a *App) SaveLastSeenVersion(version string) {
	dir, err := configDir()
	if err != nil {
		log.Printf("[updater] Could not locate config dir: %v", err)
		return
	}
	path := filepath.Join(dir, "last_seen_version")
	if err := os.WriteFile(path, []byte(version), 0o644); err != nil {
		log.Printf("[updater] Failed to save last_seen_version: %v", err)
	}
}

// compareVersions returns true if `latest` is strictly newer than `current`.
// Both are expected to be in the form "vX.Y.Z". Falls back to string
// inequality for unexpected formats so a malformed tag never crashes.
func compareVersions(latest, current string) bool {
	norm := func(v string) string { return strings.TrimPrefix(v, "v") }
	latestParts := strings.Split(norm(latest), ".")
	currentParts := strings.Split(norm(current), ".")

	for len(latestParts) < 3 {
		latestParts = append(latestParts, "0")
	}
	for len(currentParts) < 3 {
		currentParts = append(currentParts, "0")
	}

	for i := 0; i < 3; i++ {
		var l, c int
		fmt.Sscanf(latestParts[i], "%d", &l)
		fmt.Sscanf(currentParts[i], "%d", &c)
		if l > c {
			return true
		}
		if l < c {
			return false
		}
	}
	return false
}

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
// Files will be automatically dumped to ~/Downloads/PALT.
func (a *App) AcceptOffer(transferID string) {
	a.offersMu.Lock()
	ch, ok := a.pendingOffers[transferID]
	a.offersMu.Unlock()

	if !ok {
		return
	}

	ch <- OfferResolution{Accept: true}
}

// AutoAcceptOffer automatically accepts the file for a trusted device.
func (a *App) AutoAcceptOffer(transferID string) {
	a.offersMu.Lock()
	ch, ok := a.pendingOffers[transferID]
	a.offersMu.Unlock()

	if !ok {
		return
	}

	ch <- OfferResolution{Accept: true}
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
// It opens an OS dialog allowing multiple file selection.
func (a *App) SendFile(peerIP string, peerPort int) error {
	log.Printf("[app] SendFile triggered for peer %s:%d\n", peerIP, peerPort)

	filePaths, err := wailsruntime.OpenMultipleFilesDialog(a.ctx, wailsruntime.OpenDialogOptions{
		Title: "Select Files to Send via PALT",
	})
	
	if err != nil {
		log.Printf("[app] OpenMultipleFilesDialog error: %v\n", err)
		return err
	}
	if len(filePaths) == 0 {
		log.Printf("[app] OpenMultipleFilesDialog cancelled by user\n")
		return nil
	}

	log.Printf("[app] User selected %d files to send.", len(filePaths))

	transferID := generateTransferID()
	hostname, _ := os.Hostname()

	// Notify UI right away so it can pop up the progress bar
	wailsruntime.EventsEmit(a.ctx, "transfer_started", map[string]interface{}{
		"transferId": transferID,
		"senderName": hostname,
		"direction":  "outgoing",
	})

	// Run network operation async
	go func() {
		err := transfer.SendFiles(peerIP, peerPort, filePaths, transferID, hostname, func(written, total int64, sentItems, totalItems int) {
			wailsruntime.EventsEmit(a.ctx, "transfer_progress", map[string]interface{}{
				"transferId": transferID,
				"written":    written,
				"total":      total,
				"sentItems":  sentItems,
				"totalItems": totalItems,
			})
		})

		if err != nil {
			log.Printf("[app] SendFiles error: %v", err)
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
