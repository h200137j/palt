// input_app.go turns a paired phone into a touchpad and keyboard for this
// computer. The phone starts a session when its touchpad screen opens
// (GNOME asks the first time), streams pointer, scroll and key events
// while it is open, and stops it when the screen closes.
//
// Packet types (must match mobile/lib/features/remote_input.dart):
//
//	input.start   phone → desktop  {} → {error?}   (request)
//	input.stop    phone → desktop  {}
//	input.move    phone → desktop  {dx, dy}        pointer, in pixels
//	input.button  phone → desktop  {button, state} left/right/middle; click/down/up
//	input.scroll  phone → desktop  {dx, dy, finish?}
//	input.key     phone → desktop  {key, mods?}    key: name below or one character;
//	                                               mods: ctrl, alt, shift, super
//	input.text    phone → desktop  {text}
package main

import (
	"errors"
	"log"
	"sync/atomic"

	"palt/internal/link"
)

var errInputStopped = errors.New("remote control isn't running")

// keysyms for the named keys a phone can send.
var keysyms = map[string]uint32{
	"Return": 0xff0d, "BackSpace": 0xff08, "Tab": 0xff09, "Escape": 0xff1b, "Delete": 0xffff,
	"Home": 0xff50, "Left": 0xff51, "Up": 0xff52, "Right": 0xff53, "Down": 0xff54,
	"Page_Up": 0xff55, "Page_Down": 0xff56, "End": 0xff57, "Insert": 0xff63, "Print": 0xff61,
	"space": 0x20, "Menu": 0xff67,
	"F1": 0xffbe, "F2": 0xffbf, "F3": 0xffc0, "F4": 0xffc1, "F5": 0xffc2, "F6": 0xffc3,
	"F7": 0xffc4, "F8": 0xffc5, "F9": 0xffc6, "F10": 0xffc7, "F11": 0xffc8, "F12": 0xffc9,
	"Super_L": 0xffeb,
}

var modKeysyms = map[string]uint32{"ctrl": 0xffe3, "shift": 0xffe1, "alt": 0xffe9, "super": 0xffeb}

// runeKeysym is the keysym that types r.
func runeKeysym(r rune) uint32 {
	switch {
	case r == '\n':
		return keysyms["Return"]
	case r == '\t':
		return keysyms["Tab"]
	case r >= 0x20 && r <= 0x7e, r >= 0xa0 && r <= 0xff:
		return uint32(r) // Latin-1 keysyms are the code point
	}
	return 0x01000000 | uint32(r)
}

func (a *App) setupRemoteInput() {
	var restarting atomic.Bool
	// After the idle timeout the session is gone; the next event starts it
	// again in the background (no dialog, thanks to the saved token) and is
	// dropped.
	check := func(err error) {
		if errors.Is(err, errInputStopped) && restarting.CompareAndSwap(false, true) {
			go func() {
				defer restarting.Store(false)
				if err := startInput(); err != nil {
					log.Printf("[input] restart: %v", err)
				}
			}()
		}
	}

	a.links.Handle("input.start", func(l *link.Link, p link.Packet) {
		go func() {
			err := startInput()
			reply := map[string]string{}
			if err != nil {
				reply["error"] = err.Error()
			}
			log.Printf("[input] %s started remote control: %v", l.Peer.Name, err)
			l.SendID("input.start.reply", p.ID, reply)
		}()
	})
	a.links.Handle("input.stop", func(l *link.Link, p link.Packet) { stopInput() })
	a.links.Handle("input.move", func(l *link.Link, p link.Packet) {
		var b struct{ DX, DY float64 }
		if p.Decode(&b) == nil {
			check(inputMove(b.DX, b.DY))
		}
	})
	a.links.Handle("input.button", func(l *link.Link, p link.Packet) {
		var b struct{ Button, State string }
		if p.Decode(&b) != nil {
			return
		}
		switch b.State {
		case "down":
			check(inputButton(b.Button, true))
		case "up":
			check(inputButton(b.Button, false))
		default:
			if err := inputButton(b.Button, true); err != nil {
				check(err)
				return
			}
			inputButton(b.Button, false)
		}
	})
	a.links.Handle("input.scroll", func(l *link.Link, p link.Packet) {
		var b struct {
			DX, DY float64
			Finish bool
		}
		if p.Decode(&b) == nil {
			check(inputScroll(b.DX, b.DY, b.Finish))
		}
	})
	a.links.Handle("input.key", func(l *link.Link, p link.Packet) {
		var b struct {
			Key  string
			Mods []string
		}
		if p.Decode(&b) != nil {
			return
		}
		sym, ok := keysyms[b.Key]
		if !ok {
			r := []rune(b.Key)
			if len(r) != 1 {
				return
			}
			sym = runeKeysym(r[0])
		}
		var held []uint32
		for _, m := range b.Mods {
			if s, ok := modKeysyms[m]; ok {
				if err := inputKeysym(s, true); err != nil {
					check(err)
					return
				}
				held = append(held, s)
			}
		}
		if err := inputKeysym(sym, true); err != nil {
			check(err)
		} else {
			inputKeysym(sym, false)
		}
		for i := len(held) - 1; i >= 0; i-- {
			inputKeysym(held[i], false)
		}
	})
	a.links.Handle("input.text", func(l *link.Link, p link.Packet) {
		var b struct{ Text string }
		if p.Decode(&b) != nil {
			return
		}
		for _, r := range b.Text {
			sym := runeKeysym(r)
			if err := inputKeysym(sym, true); err != nil {
				check(err)
				return
			}
			inputKeysym(sym, false)
		}
	})
}
