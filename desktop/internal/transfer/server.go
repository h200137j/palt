package transfer

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
)

// Server handles incoming PALT TCP connections and file downloads.
type Server struct {
	port     int
	listener net.Listener
	running  bool

	// OnOffer blockingly decides whether to accept an incoming file.
	// Returning an empty or error savePath constitutes a rejection.
	OnOffer func(meta Metadata) (accept bool, savePath string)

	// OnProgress provides real-time chunk progress back to the UI.
	OnProgress func(transferID string, written int64, total int64)
}

// NewServer initializes a TCP receiver.
func NewServer(port int) *Server {
	return &Server{
		port: port,
	}
}

// Start opens the TCP listener loop in a background goroutine.
func (s *Server) Start() error {
	addr := fmt.Sprintf("0.0.0.0:%d", s.port)
	l, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	s.listener = l
	s.running = true

	log.Printf("[TransferServer] Listening for chunks on %s\n", addr)

	go s.acceptLoop()
	return nil
}

// Stop halts the listener.
func (s *Server) Stop() {
	s.running = false
	if s.listener != nil {
		s.listener.Close()
	}
}

func (s *Server) acceptLoop() {
	for s.running {
		conn, err := s.listener.Accept()
		if err != nil {
			if s.running {
				log.Printf("[TransferServer] Accept Error: %v\n", err)
			}
			continue
		}

		go s.handleConnection(conn)
	}
}

func (s *Server) handleConnection(conn net.Conn) {
	defer conn.Close()

	// 1. Read the HTTP-like JSON Handshake Frame
	meta, err := ReadOffer(conn)
	if err != nil {
		log.Printf("[TransferServer] Failed to read offer protocol: %v\n", err)
		return
	}

	if meta.Action != ActionOffer {
		log.Printf("[TransferServer] Unknown action: %v\n", meta.Action)
		return
	}

	// 2. Surface to UI and Wait for Verdict (blocking)
	var accept bool
	var savePath string

	if s.OnOffer != nil {
		accept, savePath = s.OnOffer(*meta)
	} else {
		// Auto-reject if not hooked up
		accept = false
	}

	// 3. Reject Route
	if !accept || savePath == "" {
		conn.Write([]byte{ResponseReject})
		return
	}

	// 4. Accept Route
	_, err = conn.Write([]byte{ResponseAccept})
	if err != nil {
		log.Printf("[TransferServer] Failed to send Accept byte: %v\n", err)
		return
	}

	// 5. Open File Destination locally
	file, err := os.Create(savePath)
	if err != nil {
		log.Printf("[TransferServer] Failed to create output file %s: %v\n", savePath, err)
		return
	}
	defer file.Close()

	// 6. IO Chunk Copy Loop with Tracker
	tracker := &TrackingWriter{
		Out:           file,
		Total:         meta.FileSize,
		Written:       0,
		BroadcastStep: meta.FileSize / 100, // Emit roughly 1% increments
		OnProgress: func(written int64, total int64) {
			if s.OnProgress != nil {
				s.OnProgress(meta.TransferID, written, total)
			}
		},
	}

	if tracker.BroadcastStep == 0 {
		tracker.BroadcastStep = 1024 * 1024 // Fallback 1MB if too small
	}

	copied, err := io.CopyN(tracker, conn, meta.FileSize)
	if err != nil && err != io.EOF {
		log.Printf("[TransferServer] Interrupted mid-transfer: only read %d/%d bytes: %v\n", copied, meta.FileSize, err)
		return
	}

	log.Printf("[TransferServer] Transfer %s complete, wrote %d bytes down.\n", meta.TransferID, copied)
}
