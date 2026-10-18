//go:build !linux && !darwin

// notify_other.go: desktop notifications are Linux and macOS only for now.
package main

type Notification struct {
	Title, Body, Icon string
	Actions           []NotifyAction
	OnAction          func(key string)
	Urgent            bool
	Replaces          uint32
	OnClosed          func(byUser bool)
	Silent            bool
	Category          string
}

type NotifyAction struct{ Key, Label string }

func notify(Notification) uint32 { return 0 }

func closeNotification(uint32) {}
