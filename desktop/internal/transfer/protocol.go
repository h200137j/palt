package transfer

import (
	"encoding/json"
	"io"
)

// Port defines the default TCP port for the PALT file transfer protocol.
// This perfectly aligns with the advertised mDNS port.
const Port = 9876

// MaxOfferSize sets an upper limit on the JSON handshake size (8KB) to prevent overflow attacks.
const MaxOfferSize = 8192

// Action values for the handshake
const (
	ActionOffer = "offer"
)

// Response Bytes
const (
	ResponseReject byte = 0x00
	ResponseAccept byte = 0x01
)

type FileMeta struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
}

// Metadata models the JSON handshake sent right after connection.
type Metadata struct {
	Action     string     `json:"action"` // "offer" implies batch
	TransferID string     `json:"transferId"`
	Files      []FileMeta `json:"files"`
	TotalSize  int64      `json:"totalSize"`
	SenderName string     `json:"senderName"`
}

// ReadOffer parses the exact 4-byte length header and subsequent JSON payload.
func ReadOffer(r io.Reader) (*Metadata, error) {
	// 1. Read 4-byte big-endian length prefix
	var length uint32
	lengthBuf := make([]byte, 4)
	if _, err := io.ReadFull(r, lengthBuf); err != nil {
		return nil, err
	}
	length = uint32(lengthBuf[3]) | uint32(lengthBuf[2])<<8 | uint32(lengthBuf[1])<<16 | uint32(lengthBuf[0])<<24

	if length > MaxOfferSize {
		return nil, io.ErrShortBuffer // Protective limit
	}

	// 2. Read exact JSON payload string
	jsonBuf := make([]byte, length)
	if _, err := io.ReadFull(r, jsonBuf); err != nil {
		return nil, err
	}

	// 3. Unmarshal
	var meta Metadata
	if err := json.Unmarshal(jsonBuf, &meta); err != nil {
		return nil, err
	}

	return &meta, nil
}

// WriteOffer serialized the Metadata with the 4-byte prefix frame to the network output stream.
func WriteOffer(w io.Writer, meta *Metadata) error {
	jsonBytes, err := json.Marshal(meta)
	if err != nil {
		return err
	}

	length := uint32(len(jsonBytes))

	// Write 4-byte length prefix (big-endian)
	if err := writeLengthPrefix(w, length); err != nil {
		return err
	}

	// Write JSON payload
	if _, err := w.Write(jsonBytes); err != nil {
		return err
	}

	return nil
}

func writeLengthPrefix(w io.Writer, length uint32) error {
	prefix := []byte{
		byte(length >> 24),
		byte(length >> 16),
		byte(length >> 8),
		byte(length),
	}
	_, err := w.Write(prefix)
	return err
}

// TrackingWriter is a custom io.Writer decorator that triggers callbacks on byte progression.
type TrackingWriter struct {
	Out           io.Writer
	Total         int64
	Written       int64
	OnProgress    func(written int64, total int64)
	BroadcastStep int64 // Throttle emit frequency
	lastBroadcast int64
}

func (tw *TrackingWriter) Write(p []byte) (n int, err error) {
	n, err = tw.Out.Write(p)
	tw.Written += int64(n)

	if tw.OnProgress != nil && tw.Written-tw.lastBroadcast >= tw.BroadcastStep || tw.Written == tw.Total {
		tw.OnProgress(tw.Written, tw.Total)
		tw.lastBroadcast = tw.Written
	}

	return n, err
}

// TrackingReader is the read-side decorator equivalent of TrackingWriter
type TrackingReader struct {
	In            io.Reader
	Total         int64
	ReadAmt       int64
	OnProgress    func(read int64, total int64)
	BroadcastStep int64
	lastBroadcast int64
}

func (tr *TrackingReader) Read(p []byte) (n int, err error) {
	n, err = tr.In.Read(p)
	tr.ReadAmt += int64(n)

	if tr.OnProgress != nil && tr.ReadAmt-tr.lastBroadcast >= tr.BroadcastStep || tr.ReadAmt == tr.Total {
		tr.OnProgress(tr.ReadAmt, tr.Total)
		tr.lastBroadcast = tr.ReadAmt
	}

	return n, err
}
