package models

import "time"

type HistoryFile struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
}

type HistoryEntry struct {
	ID             string        `json:"id"`
	PartnerName    string        `json:"partnerName"`
	Files          []HistoryFile `json:"files"`
	TotalSize      int64         `json:"totalSize"`
	Direction      string        `json:"direction"` // "incoming" or "outgoing"
	Timestamp      time.Time     `json:"timestamp"`
	Status         string        `json:"status"`         // "completed" or "error"
	ErrorMessage   string        `json:"errorMessage"`   // optional
	DurationMillis int64         `json:"durationMillis"` // how long the transfer took
}
