// textfocus_linux.go follows keyboard focus through AT-SPI, the
// accessibility bus, so the phone's keyboard can open by itself when a text
// field on this computer gets focus. Only the role and state of the focused
// object are read, never its text.
//
// GTK and Qt apps report focus; Chromium, Electron and Firefox only when
// their accessibility support is on, and most terminals not at all. The
// keyboard button on the phone covers those.
package main

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	atspiStateEditable  = 7
	atspiStateEnabled   = 8
	atspiStateSensitive = 24
	atspiStateReadOnly  = 43
	atspiRolePassword   = 40
	atspiRoleTerminal   = 60
	atspiFocusEvent     = "object:state-changed:focused"
)

var textFocus struct {
	sync.Mutex
	conn *dbus.Conn                    // accessibility bus, nil when not watching
	send func(editable, password bool) // where focus changes go
}

// atspiClassify reads an object's state bits and role.
func atspiClassify(state []uint32, role uint32) (editable, password bool) {
	has := func(bit uint) bool {
		w := int(bit / 32)
		return w < len(state) && state[w]>>(bit%32)&1 == 1
	}
	password = role == atspiRolePassword
	usable := has(atspiStateEnabled) || has(atspiStateSensitive)
	editable = usable && ((has(atspiStateEditable) && !has(atspiStateReadOnly)) || password || role == atspiRoleTerminal)
	return editable, password
}

// watchTextFocus starts reporting text focus to send, replacing any earlier
// receiver. Best effort: without an accessibility bus nothing is reported.
func watchTextFocus(send func(editable, password bool)) {
	textFocus.Lock()
	defer textFocus.Unlock()
	textFocus.send = send
	if textFocus.conn != nil {
		return
	}
	c, err := atspiConnect()
	if err != nil {
		log.Printf("[input] text focus unavailable: %v", err)
		return
	}
	textFocus.conn = c
	go runTextFocus(c)
}

// stopTextFocus stops reporting. The registry forgets our event
// registration when the connection closes.
func stopTextFocus() {
	textFocus.Lock()
	defer textFocus.Unlock()
	if textFocus.conn != nil {
		textFocus.conn.Close()
	}
	textFocus.conn, textFocus.send = nil, nil
}

func atspiConnect() (*dbus.Conn, error) {
	session, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}
	var addr string
	if err := session.Object("org.a11y.Bus", "/org/a11y/bus").Call("org.a11y.Bus.GetAddress", 0).Store(&addr); err != nil {
		return nil, err
	}
	c, err := dbus.Dial(addr)
	if err != nil {
		return nil, err
	}
	if err := c.Auth(nil); err != nil {
		c.Close()
		return nil, err
	}
	if err := c.Hello(); err != nil {
		c.Close()
		return nil, err
	}
	if err := c.AddMatchSignal(
		dbus.WithMatchInterface("org.a11y.atspi.Event.Object"),
		dbus.WithMatchMember("StateChanged"),
		dbus.WithMatchArg(0, "focused"),
	); err != nil {
		c.Close()
		return nil, err
	}
	// Toolkits only emit events someone registered for.
	reg := c.Object("org.a11y.atspi.Registry", "/org/a11y/atspi/registry")
	if reg.Call("org.a11y.atspi.Registry.RegisterEvent", 0, atspiFocusEvent, []string{}, "").Err != nil {
		reg.Call("org.a11y.atspi.Registry.RegisterEvent", 0, atspiFocusEvent)
	}
	return c, nil
}

func runTextFocus(c *dbus.Conn) {
	ch := make(chan *dbus.Signal, 64)
	c.Signal(ch)
	current := "" // sender+path of the focused text field, "" none
	report := func(editable, password bool) {
		textFocus.Lock()
		send := textFocus.send
		textFocus.Unlock()
		if send != nil {
			send(editable, password)
		}
	}
	for s := range ch {
		if len(s.Body) < 2 {
			continue
		}
		if kind, _ := s.Body[0].(string); kind != "focused" {
			continue
		}
		gained, _ := s.Body[1].(int32)
		key := s.Sender + string(s.Path)
		if gained != 1 {
			if key == current {
				current = ""
				report(false, false)
			}
			continue
		}
		// An app that hangs must not stall focus tracking.
		ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
		obj := c.Object(s.Sender, s.Path)
		var state []uint32
		err := obj.CallWithContext(ctx, "org.a11y.atspi.Accessible.GetState", 0).Store(&state)
		var role uint32
		if err == nil {
			obj.CallWithContext(ctx, "org.a11y.atspi.Accessible.GetRole", 0).Store(&role)
		}
		cancel()
		if err != nil {
			continue
		}
		editable, password := atspiClassify(state, role)
		if editable {
			current = key
			report(true, password)
		} else if current != "" {
			current = ""
			report(false, false)
		}
	}
}
