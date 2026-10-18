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
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"

	"palt/internal/discovery"
	"palt/internal/link"
	"palt/internal/models"
	"palt/internal/pairing"
	"palt/internal/relay"
	"palt/internal/thumbs"
	"palt/internal/transfer"
)

// AppVersion is the canonical version string for this build.
// Bump this manually to match the git tag when cutting a release.
const AppVersion = "v2.5.0"

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
	relay          *relay.Client
	relayMu        sync.Mutex
	probeKick      chan struct{}
	pendingOffers  map[string]chan OfferResolution
	startTime      map[string]time.Time
	offersMu       sync.Mutex

	pair   pairing.Pairing
	pairMu sync.Mutex

	links       *link.Manager
	knownMu     sync.Mutex
	connectKick chan struct{}

	// trayEnabled is set before startup when a tray host is running.
	trayEnabled bool
	// windowHidden is true while the window sits in the tray; quitting
	// lets the close handler through.
	windowHidden atomic.Bool
	quitting     atomic.Bool

	features featureState
	notes    notificationState
	calls    callState
	clip     clipboardState
	media    mediaState
	messages messagesState

	startupErr string
	tray       trayState
}

// NewApp constructs an App instance. Wails calls this during startup.
func NewApp() *App {
	return &App{
		pendingOffers: make(map[string]chan OfferResolution),
		startTime:     make(map[string]time.Time),
		probeKick:     make(chan struct{}, 1),
		connectKick:   make(chan struct{}, 1),
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

	svc, err := discovery.NewService(ctx, hostname, a.pairing().DeviceID, paltPort, hostOS, func() {
		a.emitPeers()
		a.kickConnector()
	})
	if err != nil {
		a.startupFailed("PALT can't find devices", "Discovery didn't start: "+err.Error())
	} else {
		a.discovery = svc
	}

	// Initialize Custom TCP Transfer Server
	a.transferServer = transfer.NewServer(paltPort)
	a.setupLinks()
	a.setupFeatures()
	a.setupNotificationSync()
	a.setupCalls()
	a.setupClipboard()
	a.setupWifiShare()
	a.setupMedia()
	a.setupMessages()
	a.setupUnlock()
	a.setupCommands()
	a.setupKeepAwake()
	a.setupProximityLock()
	a.setupBluetooth()
	a.setupRemoteInput()
	a.transferServer.OnOffer = func(meta transfer.Metadata) bool {
		// Paired devices proved they hold our key: their files come straight in.
		if meta.Paired {
			a.offersMu.Lock()
			a.startTime[meta.TransferID] = time.Now()
			a.offersMu.Unlock()
			return true // auto-accept immediately
		}

		offerChan := make(chan OfferResolution, 1)

		a.offersMu.Lock()
		a.pendingOffers[meta.TransferID] = offerChan
		a.offersMu.Unlock()

		// Tell React UI a device wants to send some files
		wailsruntime.EventsEmit(a.ctx, "transfer_offer", meta)
		a.showWindow()

		// Wait indefinitely for user to click Accept or Reject in the UI
		res := <-offerChan

		a.offersMu.Lock()
		delete(a.pendingOffers, meta.TransferID)
		if res.Accept {
			a.startTime[meta.TransferID] = time.Now()
		}
		a.offersMu.Unlock()

		return res.Accept
	}

	a.transferServer.OnComplete = func(meta transfer.Metadata, savedPaths []string) {
		a.offersMu.Lock()
		start, ok := a.startTime[meta.TransferID]
		delete(a.startTime, meta.TransferID)
		a.offersMu.Unlock()

		duration := time.Since(start)
		if !ok {
			duration = 0
		}

		a.logHistory(models.HistoryEntry{
			ID:             meta.TransferID,
			PartnerName:    meta.SenderName,
			TotalSize:      meta.TotalSize,
			Direction:      "incoming",
			Timestamp:      time.Now(),
			Status:         "completed",
			DurationMillis: duration.Milliseconds(),
			Files:          a.toHistoryFiles(meta.Files, savedPaths),
			Route:          meta.Route,
		})
		go a.scanForWifiQR(savedPaths, meta.SenderName)
		openArrivedPhoto(meta.SenderName, savedPaths)
	}

	a.transferServer.OnError = func(meta transfer.Metadata, savedPaths []string, err error) {
		a.offersMu.Lock()
		start, ok := a.startTime[meta.TransferID]
		delete(a.startTime, meta.TransferID)
		a.offersMu.Unlock()

		duration := time.Since(start)
		if !ok {
			duration = 0
		}

		a.logHistory(models.HistoryEntry{
			ID:             meta.TransferID,
			PartnerName:    meta.SenderName,
			TotalSize:      meta.TotalSize,
			Direction:      "incoming",
			Timestamp:      time.Now(),
			Status:         "error",
			ErrorMessage:   err.Error(),
			DurationMillis: duration.Milliseconds(),
			Files:          a.toHistoryFiles(meta.Files, savedPaths),
			Route:          meta.Route,
		})
	}

	a.transferServer.OnText = func(meta transfer.Metadata) {
		// Auto-copy is opt-in per device and only honoured for paired
		// devices, so an arbitrary LAN peer can't overwrite the clipboard.
		copied := false
		if meta.Paired && a.isAutoCopy(meta.SenderName) {
			if err := a.setClipboard(meta.Text); err != nil {
				log.Printf("[app] Auto-copy failed: %v", err)
			} else {
				copied = true
			}
		}

		a.logHistory(models.HistoryEntry{
			ID:          meta.TransferID,
			PartnerName: meta.SenderName,
			Files:       []models.HistoryFile{},
			TotalSize:   int64(len(meta.Text)),
			Direction:   "incoming",
			Timestamp:   time.Now(),
			Status:      "completed",
			Kind:        "text",
			Text:        meta.Text,
			Copied:      copied,
			Route:       meta.Route,
		})
		wailsruntime.EventsEmit(a.ctx, "text_received", map[string]interface{}{
			"senderName": meta.SenderName,
			"text":       meta.Text,
			"copied":     copied,
			"route":      meta.Route,
		})
		a.notifyText(meta.SenderName, meta.Text, copied)
	}

	a.transferServer.OnProgress = func(meta transfer.Metadata, written int64, total int64, sentItems int, totalItems int, currentFile string) {
		transferID := meta.TransferID
		a.offersMu.Lock()
		start, ok := a.startTime[transferID]
		a.offersMu.Unlock()

		var speed float64 = 0
		if ok {
			elapsed := time.Since(start).Seconds()
			if elapsed > 0 {
				speed = float64(written) / elapsed
			}
		}

		wailsruntime.EventsEmit(a.ctx, "transfer_progress", map[string]interface{}{
			"transferId":  transferID,
			"written":     written,
			"total":       total,
			"sentItems":   sentItems,
			"totalItems":  totalItems,
			"currentFile": currentFile,
			"speed":       speed,
			"route":       meta.Route,
		})
	}

	if err := a.transferServer.Start(); err != nil {
		a.startupFailed("PALT can't receive anything",
			fmt.Sprintf("Port %d is in use by another program (%v). Close it and restart PALT.", paltPort, err))
	}

	a.startRelay()
	go a.runLANProbe()
	go a.runConnector()
	go a.watchNetwork()

	ensureAutostart()
	a.startTray()

	// A terminate signal (logout, shutdown, kill) really quits, past the
	// close-to-tray handler. Not SIGHUP: catching it would also undo the
	// "ignore hangups" of a launcher, and a closing terminal would quit PALT.
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
		<-sig
		a.quit()
	}()

	log.Println("[app] PALT started successfully.")
	if wd, err := os.Getwd(); err == nil {
		a.handleArgs(os.Args[1:], wd)
	}
}

// shutdown is called by Wails when the window is closed.
func (a *App) shutdown(ctx context.Context) {
	a.stopTray()
	if a.links != nil {
		a.links.CloseAll()
	}
	if a.discovery != nil {
		a.discovery.Stop()
	}
	if a.transferServer != nil {
		a.transferServer.Stop()
	}
	a.stopRelay()
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

	// Find the asset matching this platform (.exe on Windows, .deb elsewhere).
	assetSuffix := ".deb"
	if runtime.GOOS == "windows" {
		assetSuffix = ".exe"
	}
	downloadURL := ""
	for _, asset := range release.Assets {
		if strings.HasSuffix(asset.Name, assetSuffix) {
			downloadURL = asset.BrowserDownloadURL
			break
		}
	}
	// Fall back to the releases page if no matching asset is attached.
	if downloadURL == "" {
		downloadURL = "https://github.com/h200137j/palt/releases/latest"
	}

	log.Printf("[updater] Update available: %s → %s", AppVersion, latest)
	return UpdateInfo{
		IsNewer:       true,
		LatestVersion: latest,
		DownloadURL:   downloadURL,
		ReleaseNotes:  plainReleaseNotes(release.Body),
	}
}

// GetReleaseNotes returns the notes of one release (this version's, for
// "What's new") as plain text; "" when offline.
func (a *App) GetReleaseNotes(tag string) string {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/repos/h200137j/palt/releases/tags/"+url.PathEscape(tag), nil)
	if err != nil {
		return ""
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "palt-desktop/"+AppVersion)
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	var release struct {
		Body string `json:"body"`
	}
	if resp.StatusCode != http.StatusOK || json.NewDecoder(resp.Body).Decode(&release) != nil {
		return ""
	}
	return plainReleaseNotes(release.Body)
}

// plainReleaseNotes turns release notes markdown into plain text: bullets
// as "•", no **bold** markers, no "Full Changelog" link.
func plainReleaseNotes(md string) string {
	var out []string
	for _, l := range strings.Split(md, "\n") {
		if strings.Contains(l, "Full Changelog") {
			continue
		}
		l = strings.ReplaceAll(strings.TrimRight(l, "\r"), "**", "")
		if t := strings.TrimLeft(l, " "); strings.HasPrefix(t, "- ") || strings.HasPrefix(t, "* ") {
			l = "• " + t[2:]
		}
		out = append(out, l)
	}
	return strings.TrimSpace(strings.Join(out, "\n"))
}

// showWindow brings the window back from the tray or a minimised state.
func (a *App) showWindow() {
	a.windowHidden.Store(false)
	wailsruntime.WindowShow(a.ctx)
	wailsruntime.WindowUnminimise(a.ctx)
}

func (a *App) hideWindow() {
	a.windowHidden.Store(true)
	wailsruntime.WindowHide(a.ctx)
}

// quit ends PALT, past the close-to-tray handler.
func (a *App) quit() {
	a.quitting.Store(true)
	wailsruntime.Quit(a.ctx)
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

// GetPeers returns the peers on the LAN plus those only reachable through
// the relay. Each carries Via so the UI can show the route.
func (a *App) GetPeers() []models.Peer {
	return a.mergedPeers()
}

// lanIP is the address other devices on the network reach this one at: the
// source address of the default route. Nothing is sent; falls back to
// loopback when offline.
func lanIP() string {
	conn, err := net.Dial("udp4", "192.0.2.1:9")
	if err != nil {
		return "127.0.0.1"
	}
	defer conn.Close()
	return conn.LocalAddr().(*net.UDPAddr).IP.String()
}

// GetLocalDevice returns metadata about this device for display in the UI.
func (a *App) GetLocalDevice() models.Peer {
	hostname, _ := os.Hostname()
	return models.Peer{
		ID:         "local",
		DeviceName: hostname,
		IPAddress:  lanIP(),
		Port:       paltPort,
		OS:         runtime.GOOS,
		DeviceID:   a.pairing().DeviceID,
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

// autoCopyFile returns the path to the auto-copy devices JSON file.
func (a *App) autoCopyFile() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "autocopy.json")
}

func (a *App) isAutoCopy(name string) bool {
	for _, n := range readNameList(a.autoCopyFile()) {
		if n == name {
			return true
		}
	}
	return false
}

// GetAutoCopyDevices returns the devices whose incoming texts are copied to
// the clipboard automatically.
func (a *App) GetAutoCopyDevices() []string {
	return readNameList(a.autoCopyFile())
}

// SetAutoCopy turns clipboard auto-copy on or off for a device. It only
// takes effect for paired devices.
func (a *App) SetAutoCopy(name string, enabled bool) error {
	file := a.autoCopyFile()
	if file == "" {
		return fmt.Errorf("could not locate config directory")
	}
	var out []string
	for _, n := range readNameList(file) {
		if n != name {
			out = append(out, n)
		}
	}
	if enabled {
		out = append(out, name)
	}
	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(file, data, 0o644)
}

// readNameList loads a JSON array of device names; missing or bad files read as empty.
func readNameList(file string) []string {
	names := []string{}
	if file == "" {
		return names
	}
	if data, err := os.ReadFile(file); err == nil {
		_ = json.Unmarshal(data, &names)
	}
	return names
}

// aliasesFile returns the path to the device aliases JSON file.
func (a *App) aliasesFile() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "aliases.json")
}

// GetAliases returns the map of device names to custom nicknames.
func (a *App) GetAliases() map[string]string {
	af := a.aliasesFile()
	if af == "" {
		return map[string]string{}
	}
	data, err := os.ReadFile(af)
	if err != nil {
		return map[string]string{}
	}
	var aliases map[string]string
	if err := json.Unmarshal(data, &aliases); err != nil {
		return map[string]string{}
	}
	return aliases
}

// SetAlias assigns a custom nickname to a device name.
func (a *App) SetAlias(deviceName, alias string) {
	af := a.aliasesFile()
	if af == "" {
		return
	}
	aliases := a.GetAliases()
	if alias == "" {
		delete(aliases, deviceName)
	} else {
		aliases[deviceName] = alias
	}
	if data, err := json.MarshalIndent(aliases, "", "  "); err == nil {
		_ = os.WriteFile(af, data, 0o644)
	}
	a.refreshTray()
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
// It opens an OS dialog allowing multiple file selection. peerName is the
// peer's broadcast name, recorded in history so per-device threads line up.
func (a *App) SendFile(peerIP string, peerPort int, peerName string) error {
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
	return a.sendPaths(peerIP, peerPort, peerName, filePaths)
}

// SendFilePaths is called by React when files are drag-and-dropped onto a
// PeerCard. The paths come from the Wails OnFileDrop runtime event.
func (a *App) SendFilePaths(peerIP string, peerPort int, peerName string, filePaths []string) error {
	log.Printf("[app] SendFilePaths triggered for peer %s:%d (%d files)\n", peerIP, peerPort, len(filePaths))
	if len(filePaths) == 0 {
		return nil
	}
	return a.sendPaths(peerIP, peerPort, peerName, filePaths)
}

// SendText delivers a text message to a peer and records it in history.
// It blocks until the peer acknowledges, so the UI can surface errors inline.
func (a *App) SendText(peerIP string, peerPort int, peerName string, text string) error {
	transferID := generateTransferID()
	hostname, _ := os.Hostname()

	route := ""
	dial := func() (net.Conn, error) {
		conn, r, err := a.dialPeer(peerIP, peerPort, peerName)
		route = r
		return conn, err
	}
	err := transfer.SendText(dial, transferID, hostname, text)

	entry := models.HistoryEntry{
		ID:          transferID,
		PartnerName: peerName,
		Files:       []models.HistoryFile{},
		TotalSize:   int64(len(text)),
		Direction:   "outgoing",
		Timestamp:   time.Now(),
		Status:      "completed",
		Kind:        "text",
		Text:        text,
		Route:       route,
	}
	if err != nil {
		log.Printf("[app] SendText error: %v", err)
		entry.Status = "error"
		entry.ErrorMessage = err.Error()
	}
	a.logHistory(entry)
	return err
}

// sendPaths streams the given local file paths to a peer, emitting the same
// transfer_* events the UI already listens to.
func (a *App) sendPaths(peerIP string, peerPort int, peerName string, filePaths []string) error {
	return a.sendPathsTo(peerIP, peerPort, peerName, filePaths, "")
}

// sendPathsTo is sendPaths into folder dest on a phone.
func (a *App) sendPathsTo(peerIP string, peerPort int, peerName string, filePaths []string, dest string) error {
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
		start := time.Now()
		route := ""
		dial := func() (net.Conn, error) {
			conn, r, err := a.dialPeer(peerIP, peerPort, peerName)
			if err == nil {
				route = r
				// Tell the UI which way this transfer is going.
				wailsruntime.EventsEmit(a.ctx, "transfer_started", map[string]interface{}{
					"transferId": transferID,
					"senderName": hostname,
					"direction":  "outgoing",
					"route":      route,
				})
			}
			return conn, err
		}
		err := transfer.SendFilesTo(dial, filePaths, dest, transferID, hostname, func(written, total int64, sentItems, totalItems int, currentFile string) {
			elapsed := time.Since(start).Seconds()
			var speed float64 = 0
			if elapsed > 0 {
				speed = float64(written) / elapsed
			}

			wailsruntime.EventsEmit(a.ctx, "transfer_progress", map[string]interface{}{
				"transferId":  transferID,
				"written":     written,
				"total":       total,
				"sentItems":   sentItems,
				"totalItems":  totalItems,
				"currentFile": currentFile,
				"speed":       speed,
				"route":       route,
			})
		})

		duration := time.Since(start)

		// Get filenames for history
		var hFiles []models.HistoryFile
		var totalSize int64
		for _, p := range filePaths {
			s, _ := os.Stat(p)
			if s != nil && !s.IsDir() {
				hFiles = append(hFiles, models.HistoryFile{Name: filepath.Base(p), Size: s.Size(), Path: p})
				totalSize += s.Size()
			}
		}

		if err != nil {
			log.Printf("[app] SendFiles error: %v", err)
			wailsruntime.EventsEmit(a.ctx, "transfer_error", map[string]interface{}{
				"transferId": transferID,
				"error":      err.Error(),
			})
			a.logHistory(models.HistoryEntry{
				ID:             transferID,
				PartnerName:    peerName,
				TotalSize:      totalSize,
				Direction:      "outgoing",
				Timestamp:      time.Now(),
				Status:         "error",
				ErrorMessage:   err.Error(),
				DurationMillis: duration.Milliseconds(),
				Files:          hFiles,
				Route:          route,
			})
		} else {
			// Ensure it completes at 100% locally
			wailsruntime.EventsEmit(a.ctx, "transfer_complete", map[string]interface{}{
				"transferId": transferID,
			})
			a.logHistory(models.HistoryEntry{
				ID:             transferID,
				PartnerName:    peerName,
				TotalSize:      totalSize,
				Direction:      "outgoing",
				Timestamp:      time.Now(),
				Status:         "completed",
				DurationMillis: duration.Milliseconds(),
				Files:          hFiles,
				Route:          route,
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

// History Helpers

func (a *App) historyFile() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "history.json")
}

func (a *App) logHistory(entry models.HistoryEntry) {
	file := a.historyFile()
	if file == "" {
		return
	}

	var history []models.HistoryEntry
	data, err := os.ReadFile(file)
	if err == nil {
		_ = json.Unmarshal(data, &history)
	}

	// Prepend new entry
	history = append([]models.HistoryEntry{entry}, history...)

	// Keep last 1000 items
	if len(history) > 1000 {
		history = history[:1000]
	}

	newData, err := json.MarshalIndent(history, "", "  ")
	if err == nil {
		_ = os.WriteFile(file, newData, 0o644)
	}

	// Notify UI a new history item is added
	wailsruntime.EventsEmit(a.ctx, "history_updated", history)
}

func (a *App) toHistoryFiles(files []transfer.FileMeta, savedPaths []string) []models.HistoryFile {
	hFiles := make([]models.HistoryFile, len(files))
	for i, f := range files {
		hFiles[i] = models.HistoryFile{Name: f.Name, Size: f.Size}
		if i < len(savedPaths) {
			hFiles[i].Path = savedPaths[i]
		}
	}
	return hFiles
}

// resolveHistoryFile finds a file referenced by history. Entries written
// before paths were recorded fall back to ~/Downloads/PALT/<name>.
func resolveHistoryFile(path, name string) (string, error) {
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		path = filepath.Join(home, "Downloads", "PALT", filepath.Base(name))
	}
	if _, err := os.Stat(path); err != nil {
		return "", fmt.Errorf("%s is no longer at %s", filepath.Base(path), filepath.Dir(path))
	}
	return path, nil
}

// OpenHistoryFile opens a transferred file with the system default app.
func (a *App) OpenHistoryFile(path, name string) error {
	p, err := resolveHistoryFile(path, name)
	if err != nil {
		return err
	}
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", p)
	case "darwin":
		cmd = exec.Command("open", p)
	default:
		cmd = exec.Command("xdg-open", p)
	}
	return cmd.Start()
}

// MediaPreview is an inline preview for a picture or video in a thread.
type MediaPreview struct {
	URL      string  `json:"url"`      // data: URL of a small JPEG
	Video    bool    `json:"video"`    // draw a play badge
	Duration float64 `json:"duration"` // seconds, videos only (0 = unknown)
}

// GetMediaPreview returns a small preview of a transferred picture or video
// so the thread can show it inline. It fails for other files, files no longer
// on disk, and videos when ffmpeg isn't installed; the UI then shows a plain
// file row.
func (a *App) GetMediaPreview(path, name string) (MediaPreview, error) {
	isVideo := thumbs.IsVideo(name)
	if !isVideo && !thumbs.IsImage(name) {
		return MediaPreview{}, thumbs.ErrNotImage
	}
	p, err := resolveHistoryFile(path, name)
	if err != nil {
		return MediaPreview{}, err
	}
	cacheDir := ""
	if dir, err := os.UserCacheDir(); err == nil {
		cacheDir = filepath.Join(dir, "palt", "thumbs")
	}
	var jpg []byte
	var secs float64
	if isVideo {
		jpg, secs, err = thumbs.Video(p, cacheDir)
	} else {
		jpg, err = thumbs.Get(p, cacheDir)
	}
	if err != nil {
		return MediaPreview{}, err
	}
	return MediaPreview{
		URL:      "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString(jpg),
		Video:    isVideo,
		Duration: secs,
	}, nil
}

// RevealHistoryFile opens the file manager with the file selected where the
// platform supports it, otherwise at its folder.
func (a *App) RevealHistoryFile(path, name string) error {
	p, err := resolveHistoryFile(path, name)
	if err != nil {
		return err
	}
	switch runtime.GOOS {
	case "windows":
		return exec.Command("explorer", "/select,", p).Start()
	case "darwin":
		return exec.Command("open", "-R", p).Start()
	default:
		// FileManager1 selects the file in Nautilus, Dolphin, Nemo, etc.
		uri := (&url.URL{Scheme: "file", Path: p}).String()
		err := exec.Command("dbus-send", "--session", "--print-reply",
			"--dest=org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
			"org.freedesktop.FileManager1.ShowItems", "array:string:"+uri, "string:").Run()
		if err == nil {
			return nil
		}
		return exec.Command("xdg-open", filepath.Dir(p)).Start()
	}
}

// GetHistory returns the persistent transfer log.
func (a *App) GetHistory() []models.HistoryEntry {
	file := a.historyFile()
	if file == "" {
		return []models.HistoryEntry{}
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return []models.HistoryEntry{}
	}
	var history []models.HistoryEntry
	_ = json.Unmarshal(data, &history)
	return history
}

// DeleteHistoryEntry removes one item from the local transfer log. Files on
// disk are left alone.
func (a *App) DeleteHistoryEntry(id, direction string) {
	file := a.historyFile()
	if file == "" {
		return
	}
	history := a.GetHistory()
	kept := []models.HistoryEntry{}
	for _, e := range history {
		if e.ID == id && e.Direction == direction {
			continue
		}
		kept = append(kept, e)
	}
	if data, err := json.MarshalIndent(kept, "", "  "); err == nil {
		_ = os.WriteFile(file, data, 0o644)
	}
	wailsruntime.EventsEmit(a.ctx, "history_updated", kept)
}

// ClearHistory wipes the local transfer log.
func (a *App) ClearHistory() {
	file := a.historyFile()
	if file != "" {
		_ = os.WriteFile(file, []byte("[]"), 0o644)
	}
	wailsruntime.EventsEmit(a.ctx, "history_updated", []models.HistoryEntry{})
}

// OpenDownloadFolder opens the system file explorer at ~/Downloads/PALT.
func (a *App) OpenDownloadFolder() {
	home, err := os.UserHomeDir()
	if err != nil {
		return
	}
	path := filepath.Join(home, "Downloads", "PALT")

	// Ensure the directory exists before trying to open it
	os.MkdirAll(path, 0o755)

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("explorer", path)
	case "darwin":
		cmd = exec.Command("open", path)
	default: // "linux"
		cmd = exec.Command("xdg-open", path)
	}

	if err := cmd.Start(); err != nil {
		log.Printf("[app] Failed to open download folder: %v", err)
	}
}

// startupFailed reports a startup problem that leaves PALT running with
// less: in the log, as a notification, and to the window (GetStartupError).
func (a *App) startupFailed(title, detail string) {
	log.Printf("[app] %s: %s", title, detail)
	a.startupErr = title + ". " + detail
	notify(Notification{Title: title, Body: detail, Icon: "dialog-warning", Urgent: true})
}

// GetStartupError is the problem PALT hit while starting, "" if none.
func (a *App) GetStartupError() string { return a.startupErr }
