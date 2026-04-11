package transfer

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
)

// Server handles incoming PALT TCP connections and file downloads.
type Server struct {
	port     int
	listener net.Listener
	running  bool

	// OnOffer blockingly decides whether to accept an incoming file.
	OnOffer func(meta Metadata) (accept bool)

	// OnProgress provides real-time chunk progress back to the UI.
	OnProgress func(transferID string, written int64, total int64, sentItems int, totalItems int, currentFile string)

	// OnComplete is called when a transfer finishes successfully.
	OnComplete func(meta Metadata)

	// OnError is called when a transfer fails.
	OnError func(meta Metadata, err error)
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

	if s.OnOffer != nil {
		accept = s.OnOffer(*meta)
	} else {
		accept = false
	}

	// 3. Reject Route
	if !accept {
		conn.Write([]byte{ResponseReject})
		return
	}

	// 4. Accept Route
	_, err = conn.Write([]byte{ResponseAccept})
	if err != nil {
		log.Printf("[TransferServer] Failed to send Accept byte: %v\n", err)
		return
	}

	// 5. Open Default Hardware PALT Directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Printf("[TransferServer] Could not find user home for saving: %v\n", err)
		return
	}
	downloadDir := filepath.Join(homeDir, "Downloads", "PALT")
	os.MkdirAll(downloadDir, os.ModePerm)

	// 6. IO Chunk Copy Loop
	var totalWritten int64 = 0
	totalFiles := len(meta.Files)

	for i, f := range meta.Files {
		savePath := resolveUniqueFilePath(downloadDir, f.Name)
		file, err := os.Create(savePath)
		if err != nil {
			log.Printf("[TransferServer] Failed to create output file %s: %v\n", savePath, err)
			return
		}
		
		tracker := &TrackingWriter{
			Out:           file,
			Total:         meta.TotalSize,
			Written:       totalWritten,
			BroadcastStep: meta.TotalSize / 100,
			OnProgress: func(written int64, total int64) {
				if s.OnProgress != nil {
					s.OnProgress(meta.TransferID, written, total, i+1, totalFiles, f.Name)
				}
			},
		}

		if tracker.BroadcastStep == 0 {
			tracker.BroadcastStep = 1024 * 1024 // Fallback 1MB if too small
		}

		limitReader := io.LimitReader(conn, f.Size)
		buf := make([]byte, 1024*1024) // 1MB buffer
		copied, err := io.CopyBuffer(tracker, limitReader, buf)
		file.Close()
		totalWritten += copied

		if err != nil && err != io.EOF {
			log.Printf("[TransferServer] Interrupted mid-transfer on file %s: only read %d/%d bytes: %v\n", f.Name, copied, f.Size, err)
			if s.OnError != nil {
				s.OnError(*meta, err)
			}
			return
		}

		log.Printf("[TransferServer] Streamed %s completely (%d bytes).\n", f.Name, copied)
	}
	
	log.Printf("[TransferServer] Transfer %s completely finished across %d files.\n", meta.TransferID, totalFiles)
	if s.OnComplete != nil {
		s.OnComplete(*meta)
	}
}

// resolveUniqueFilePath generates a non-colliding filename by appending (1), (2), etc.
func resolveUniqueFilePath(dir, name string) string {
	ext := filepath.Ext(name)
	base := name[:len(name)-len(ext)]

	path := filepath.Join(dir, name)
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return path
	}

	for i := 1; ; i++ {
		newName := fmt.Sprintf("%s (%d)%s", base, i, ext)
		path = filepath.Join(dir, newName)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			return path
		}
	}
}
