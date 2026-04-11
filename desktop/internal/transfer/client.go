package transfer

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
)

var (
	ErrRejected = errors.New("peer rejected the file transfer")
)

// SendFiles connects to a peer network endpoint, handshakes the batch metadata,
// and streams the chosen files sequentially from local disk.
// OnProgress tracks chunks traversing the network.
func SendFiles(peerIP string, peerPort int, filePaths []string, transferID string, senderName string, onProgress func(written int64, total int64, sentItems int, totalItems int, currentFile string)) error {
	var totalSize int64 = 0
	var metaFiles []FileMeta

	// 1. Gather local file info
	for _, path := range filePaths {
		stat, err := os.Stat(path)
		if err != nil {
			return fmt.Errorf("failed to stat file %s: %w", path, err)
		}
		if stat.IsDir() {
			continue // Skip directories for simplicity right now
		}
		
		size := stat.Size()
		totalSize += size
		metaFiles = append(metaFiles, FileMeta{
			Name: filepath.Base(path),
			Size: size,
		})
	}

	if len(metaFiles) == 0 {
		return errors.New("no valid files selected to send")
	}

	// 2. Dial TCP socket
	addr := fmt.Sprintf("%s:%d", peerIP, peerPort)
	log.Printf("[TransferClient] Dialing peer at %s", addr)
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		return fmt.Errorf("failed to dial peer: %w", err)
	}
	defer conn.Close()

	// 3. Construct and write Handshake
	meta := &Metadata{
		Action:     ActionOffer,
		TransferID: transferID,
		Files:      metaFiles,
		TotalSize:  totalSize,
		SenderName: senderName,
	}

	if err := WriteOffer(conn, meta); err != nil {
		return fmt.Errorf("failed to send handshake: %w", err)
	}

	// 4. Wait for Peer Verdict
	log.Printf("[TransferClient] Handshake sent! Waiting for %s verdict...", addr)
	verdictBuf := make([]byte, 1)
	if _, err := io.ReadFull(conn, verdictBuf); err != nil {
		return fmt.Errorf("dropped connection right before reading verdict: %w", err)
	}

	if verdictBuf[0] == ResponseReject {
		return ErrRejected
	} else if verdictBuf[0] != ResponseAccept {
		return fmt.Errorf("unexpected verdict byte from peer: 0x%x", verdictBuf[0])
	}

	// 5. Accepted! Stream files sequentially over same open socket.
	log.Printf("[TransferClient] Accepted! Sending %d files (%d bytes)...", len(metaFiles), totalSize)

	var totalRead int64 = 0
	totalFilesCount := len(filePaths)

	for i, path := range filePaths {
		file, err := os.Open(path)
		if err != nil {
			log.Printf("[TransferClient] Failed to open local file %s mid-transfer: %v", path, err)
			continue
		}
		
		stat, _ := file.Stat()
		if stat.IsDir() {
			file.Close()
			continue
		}

		tracker := &TrackingReader{
			In:            file,
			Total:         totalSize,
			ReadAmt:       totalRead,
			BroadcastStep: totalSize / 100, // roughly 1% updates
			OnProgress: func(read int64, total int64) {
				if onProgress != nil {
					onProgress(read, total, i+1, totalFilesCount, filepath.Base(path))
				}
			},
		}

		if tracker.BroadcastStep == 0 {
			tracker.BroadcastStep = 1024 * 1024 // Fallback 1MB
		}

		// 1MB buffer drastically reduces kernel syscall frequency
		buf := make([]byte, 1024*1024)
		sent, err := io.CopyBuffer(conn, tracker, buf)
		file.Close()
		totalRead += sent

		if err != nil {
			return fmt.Errorf("network interrupted mid-transfer. Wrote %d/%d bytes: %w", totalRead, totalSize, err)
		}
	}

	log.Printf("[TransferClient] Success! Wrote all %d bytes.", totalRead)
	return nil
}
