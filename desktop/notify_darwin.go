// notify_darwin.go shows desktop notifications through Notification Center
// (osascript). macOS gives scripted notifications no action buttons, so
// Actions, OnAction and OnClosed are ignored; the window offers the same
// choices.
package main

import (
	"log"
	"os/exec"
	"sync/atomic"
)

// Notification is one desktop notification.
type Notification struct {
	Title string
	Body  string
	Icon  string // ignored: Notification Center shows the app's icon
	// Actions are shown as buttons on Linux; not on macOS.
	Actions  []NotifyAction
	OnAction func(key string)
	// Urgent notifications stay until dismissed (Linux only).
	Urgent bool
	// Replaces is the ID of an earlier notification to update in place.
	Replaces uint32
	// OnClosed is never called on macOS.
	OnClosed func(byUser bool)
	// Silent notifications make no sound (e.g. updates of earlier ones).
	Silent bool
	// Category is a freedesktop category such as "im.received".
	Category string
}

type NotifyAction struct{ Key, Label string }

var lastNotifyID atomic.Uint32

// notify shows a notification and returns its ID (0 on failure).
func notify(nt Notification) uint32 {
	// Title and body go in as arguments, so they need no AppleScript quoting.
	script := `on run argv
	display notification (item 2 of argv) with title (item 1 of argv)
end run`
	if !nt.Silent {
		script = `on run argv
	display notification (item 2 of argv) with title (item 1 of argv) sound name "default"
end run`
	}
	if err := exec.Command("osascript", "-e", script, nt.Title, nt.Body).Start(); err != nil {
		log.Printf("[notify] %v", err)
		return 0
	}
	if nt.Replaces != 0 {
		return nt.Replaces
	}
	return lastNotifyID.Add(1)
}

// closeNotification: scripted notifications can't be withdrawn.
func closeNotification(uint32) {}
