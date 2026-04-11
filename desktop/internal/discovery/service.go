// Package discovery implements the mDNS (Zeroconf/Bonjour) layer for PALT.
//
// It is responsible for two concurrent jobs:
//  1. Registering (advertising) THIS device as a _palt._tcp service on the LAN.
//  2. Browsing the LAN for other _palt._tcp services and maintaining a live,
//     thread-safe registry of discovered peers.
//
// Usage:
//
//	svc, err := discovery.NewService(ctx, "MyDevice", 9000, "linux")
//	if err != nil { ... }
//	defer svc.Stop()
//
//	peers := svc.GetPeers()   // Safe to call from any goroutine.
package discovery

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"sync"
	"time"

	"github.com/grandcat/zeroconf"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"

	"palt/internal/models"
)

const (
	// serviceType is the mDNS service type advertised by every PALT instance.
	serviceType = "_palt._tcp"

	// domain is the standard mDNS local domain.
	domain = "local."

	// browseInterval is how often the browser re-scans the network.
	// Zeroconf is event-driven, so this is just a watchdog restart interval.
	browseInterval = 30 * time.Second

	// peerTTL controls how long a peer is kept in the registry after its last
	// seen announcement. If no refresh arrives within this window the peer is
	// considered gone. Slightly longer than browseInterval to avoid flapping.
	peerTTL = 90 * time.Second
)

// Service manages both the mDNS advertisement and peer discovery.
type Service struct {
	// deviceName is the human-readable name shown to peers.
	deviceName string

	// port is the TCP port this device's PALT service listens on.
	port int

	// os describes the host operating system (e.g. "linux", "android").
	os string

	// mu guards the peers map against concurrent access.
	mu sync.RWMutex

	// peers holds the currently known live peers keyed by their instance name.
	peers map[string]*trackedPeer

	// server is the active zeroconf registration (advertiser).
	server *zeroconf.Server

	// ctx / cancel control the lifetime of all background goroutines.
	ctx    context.Context
	cancel context.CancelFunc

	// wg lets Stop() wait for all goroutines to finish.
	wg sync.WaitGroup
}

// trackedPeer wraps a Peer with metadata used for TTL expiry.
type trackedPeer struct {
	peer    models.Peer
	lastSeen time.Time
}

// NewService creates and starts a PALT discovery service.
//
//   - deviceName: friendly name advertised on the network (defaults to hostname).
//   - port:       TCP port to advertise (the PALT transfer server port).
//   - hostOS:     OS string embedded in TXT records ("linux", "android", etc.).
func NewService(parentCtx context.Context, deviceName string, port int, hostOS string) (*Service, error) {
	// Fall back to the system hostname if no name was provided.
	if deviceName == "" {
		h, err := os.Hostname()
		if err != nil {
			deviceName = "palt-device"
		} else {
			deviceName = h
		}
	}

	ctx, cancel := context.WithCancel(parentCtx)

	svc := &Service{
		deviceName: deviceName,
		port:       port,
		os:         hostOS,
		peers:      make(map[string]*trackedPeer),
		ctx:        ctx,
		cancel:     cancel,
	}

	// Start advertising our own presence.
	if err := svc.startAdvertising(); err != nil {
		cancel()
		return nil, fmt.Errorf("discovery: failed to start advertising: %w", err)
	}

	// Start browsing for peers in the background.
	svc.wg.Add(1)
	go svc.browseLoop()

	// Start the TTL reaper to remove stale peers.
	svc.wg.Add(1)
	go svc.reaperLoop()

	log.Printf("[discovery] Service started: name=%q port=%d os=%s", deviceName, port, hostOS)
	return svc, nil
}

// Stop gracefully shuts down advertisement and browsing.
func (s *Service) Stop() {
	log.Println("[discovery] Stopping...")
	s.cancel()

	if s.server != nil {
		s.server.Shutdown()
	}

	s.wg.Wait()
	log.Println("[discovery] Stopped.")
}

// GetPeers returns a snapshot of the currently known peers.
// This method is safe to call from any goroutine, including the Wails runtime.
func (s *Service) GetPeers() []models.Peer {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]models.Peer, 0, len(s.peers))
	for _, tp := range s.peers {
		out = append(out, tp.peer)
	}
	return out
}

// ─── Private helpers ──────────────────────────────────────────────────────────

// startAdvertising registers this device with zeroconf.
// TXT records carry extra metadata (OS) that peers can parse.
func (s *Service) startAdvertising() error {
	// Build TXT records: key=value pairs carried in the DNS-SD TXT record.
	txtRecords := []string{
		"os=" + s.os,
		"app=palt",
	}

	server, err := zeroconf.Register(
		s.deviceName, // Instance name (shown to peers).
		serviceType,
		domain,
		s.port,
		txtRecords,
		nil, // nil = use all network interfaces.
	)
	if err != nil {
		return err
	}

	s.server = server
	log.Printf("[discovery] Advertising %s.%s on port %d", s.deviceName, serviceType, s.port)
	return nil
}

// browseLoop continuously browses for _palt._tcp peers.
// It restarts the browse session every browseInterval so that new devices
// joining the network mid-session are always detected.
func (s *Service) browseLoop() {
	defer s.wg.Done()

	for {
		s.runBrowseSession()

		select {
		case <-s.ctx.Done():
			return
		case <-time.After(browseInterval):
			// Restart browse to pick up any newly joined devices.
		}
	}
}

// runBrowseSession runs a single zeroconf browse pass for browseInterval seconds.
func (s *Service) runBrowseSession() {
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		log.Printf("[discovery] Failed to create resolver: %v", err)
		return
	}

	entries := make(chan *zeroconf.ServiceEntry)

	// Kick off the browse in its own goroutine.
	browseCtx, browseCancel := context.WithTimeout(s.ctx, browseInterval)
	defer browseCancel()

	if err := resolver.Browse(browseCtx, serviceType, domain, entries); err != nil {
		log.Printf("[discovery] Browse error: %v", err)
		return
	}

	for {
		select {
		case entry, ok := <-entries:
			if !ok {
				return
			}
			s.handleEntry(entry)

		case <-browseCtx.Done():
			return
		}
	}
}

// handleEntry processes a single mDNS service entry.
// Entries that belong to THIS device (same hostname + port) are ignored to
// prevent self-discovery.
func (s *Service) handleEntry(entry *zeroconf.ServiceEntry) {
	// Skip entries with no resolved addresses.
	if len(entry.AddrIPv4) == 0 && len(entry.AddrIPv6) == 0 {
		return
	}

	// Resolve the best IP address (prefer IPv4).
	ip := resolveIP(entry)
	if ip == "" {
		return
	}

	// Ignore ourselves.
	if entry.Instance == s.deviceName && entry.Port == s.port {
		return
	}

	// Parse TXT records for the peer OS.
	peerOS := parseTXTField(entry.Text, "os")
	if peerOS == "" {
		peerOS = "unknown"
	}

	peer := models.Peer{
		ID:         ip,
		DeviceName: entry.Instance,
		IPAddress:  ip,
		Port:       entry.Port,
		OS:         peerOS,
	}

	s.mu.Lock()
	isNew := true
	if existing, ok := s.peers[ip]; ok {
		isNew = false
		existing.lastSeen = time.Now()
		if existing.peer.DeviceName != peer.DeviceName || existing.peer.OS != peer.OS || existing.peer.Port != peer.Port {
			existing.peer = peer
			isNew = true
		}
	} else {
		s.peers[ip] = &trackedPeer{
			peer:     peer,
			lastSeen: time.Now(),
		}
	}
	s.mu.Unlock()

	if isNew {
		log.Printf("[discovery] Peer updated/added: %s (%s:%d) os=%s", peer.DeviceName, peer.IPAddress, peer.Port, peer.OS)
		wailsruntime.EventsEmit(s.ctx, "peers_changed", s.GetPeers())
	}
}

// reaperLoop removes peers that have not been seen within peerTTL.
func (s *Service) reaperLoop() {
	defer s.wg.Done()

	ticker := time.NewTicker(peerTTL / 2)
	defer ticker.Stop()

	for {
		select {
		case <-s.ctx.Done():
			return

		case <-ticker.C:
			s.evictStalePeers()
		}
	}
}

// evictStalePeers removes any peer whose lastSeen time is older than peerTTL.
func (s *Service) evictStalePeers() {
	cutoff := time.Now().Add(-peerTTL)

	s.mu.Lock()
	changed := false
	for id, tp := range s.peers {
		if tp.lastSeen.Before(cutoff) {
			log.Printf("[discovery] Peer evicted (TTL): %s", tp.peer.DeviceName)
			delete(s.peers, id)
			changed = true
		}
	}
	s.mu.Unlock()

	if changed {
		wailsruntime.EventsEmit(s.ctx, "peers_changed", s.GetPeers())
	}
}

// ─── Utility helpers ──────────────────────────────────────────────────────────

// resolveIP returns the best string IP address for a service entry.
// IPv4 is preferred over IPv6; both are validated before use.
func resolveIP(entry *zeroconf.ServiceEntry) string {
	for _, addr := range entry.AddrIPv4 {
		ip := net.IP(addr).String()
		if ip != "" && ip != "<nil>" {
			return ip
		}
	}
	for _, addr := range entry.AddrIPv6 {
		ip := net.IP(addr).String()
		if ip != "" && ip != "<nil>" {
			return ip
		}
	}
	return ""
}

// parseTXTField scans a slice of "key=value" TXT records and returns the value
// for the given key, or an empty string if not found.
func parseTXTField(records []string, key string) string {
	prefix := key + "="
	for _, r := range records {
		if len(r) > len(prefix) && r[:len(prefix)] == prefix {
			return r[len(prefix):]
		}
	}
	return ""
}
