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

// SendFile connects to a peer network endpoint, handshakes the metadata,
// and streams the chosen file from local disk.
// OnProgress tracks chunks traversing the network.
func SendFile(peerIP string, peerPort int, filePath string, transferID string, senderName string, onProgress func(written int64, total int64)) error {
	// 1. Gather local file info
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open local file: %w", err)
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat file: %w", err)
	}

	fileName := filepath.Base(filePath)
	fileSize := stat.Size()

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
		FileName:   fileName,
		FileSize:   fileSize,
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

	// 5. Accepted! Stream chunks over same open socket.
	log.Printf("[TransferClient] Accepted! Sending %d bytes...", fileSize)

	tracker := &TrackingReader{
		In:            file,
		Total:         fileSize,
		ReadAmt:       0,
		BroadcastStep: fileSize / 100, // roughly 1% updates
		OnProgress: func(read int64, total int64) {
			if onProgress != nil {
				onProgress(read, total)
			}
		},
	}

	if tracker.BroadcastStep == 0 {
		tracker.BroadcastStep = 1024 * 1024 // Fallback 1MB if < 100 bytes
	}

	// io.Copy handles buffering internally to prevent loading the whole multi-GB file into RAM.
	sent, err := io.Copy(conn, tracker)
	if err != nil {
		return fmt.Errorf("network interrupted mid-transfer. Wrote %d/%d bytes: %w", sent, fileSize, err)
	}

	log.Printf("[TransferClient] Success! Wrote all %d bytes.", sent)
	return nil
}
