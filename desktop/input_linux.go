// input_linux.go moves the pointer and types on this computer for a paired
// phone, through the xdg-desktop-portal RemoteDesktop portal. GNOME asks
// once; the restore token it hands back is saved so later sessions start
// without asking.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	portalDest  = "org.freedesktop.portal.Desktop"
	portalPath  = "/org/freedesktop/portal/desktop"
	portalRD    = "org.freedesktop.portal.RemoteDesktop"
	portalReq   = "org.freedesktop.portal.Request"
	portalSess  = "org.freedesktop.portal.Session"
	inputIdle   = 3 * time.Minute // close the session (and GNOME's indicator) after this long unused
	portalAsk   = 2 * time.Minute // how long the user has to answer GNOME's dialog
	evdevLeft   = 0x110
	evdevRight  = 0x111
	evdevMiddle = 0x112
)

var errInputDenied = errors.New("remote control was not allowed on the computer")

var remoteInput struct {
	sync.Mutex
	conn    *dbus.Conn
	session dbus.ObjectPath // "" when no session
	last    time.Time
}

// inputStarting serialises session starts. It is held while GNOME's dialog
// waits for the user, so it must never be taken by the event path.
var inputStarting struct {
	sync.Mutex
	n int // request token counter
}

func inputTokenFile() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "remote_input_token")
}

// startInput makes sure a RemoteDesktop session is running, asking GNOME
// (and the user, the first time) if needed.
func startInput() error {
	inputStarting.Lock()
	defer inputStarting.Unlock()
	remoteInput.Lock()
	remoteInput.last = time.Now()
	running := remoteInput.session != ""
	c := remoteInput.conn
	remoteInput.Unlock()
	if running {
		return nil
	}
	if c == nil {
		// A private connection, so portal signals don't mix with other users
		// of the shared session bus.
		var err error
		if c, err = dbus.ConnectSessionBus(); err != nil {
			return err
		}
		c.AddMatchSignal(dbus.WithMatchInterface(portalSess), dbus.WithMatchMember("Closed"))
		ch := make(chan *dbus.Signal, 16)
		c.Signal(ch)
		go watchInputSignals(ch)
		go closeIdleInput()
		remoteInput.Lock()
		remoteInput.conn = c
		remoteInput.Unlock()
	}
	rd := c.Object(portalDest, portalPath)

	res, err := portalRequest(c, func(token string) (dbus.ObjectPath, error) {
		var req dbus.ObjectPath
		err := rd.Call(portalRD+".CreateSession", 0, map[string]dbus.Variant{
			"handle_token":         dbus.MakeVariant(token),
			"session_handle_token": dbus.MakeVariant(token),
		}).Store(&req)
		return req, err
	})
	if err != nil {
		return err
	}
	var sessStr string
	if v, ok := res["session_handle"]; ok {
		sessStr, _ = v.Value().(string)
	}
	if sessStr == "" {
		return errors.New("the portal gave no session")
	}
	sess := dbus.ObjectPath(sessStr)

	opts := map[string]dbus.Variant{
		"types":        dbus.MakeVariant(uint32(1 | 2)), // keyboard, pointer
		"persist_mode": dbus.MakeVariant(uint32(2)),     // until revoked
	}
	if b, err := os.ReadFile(inputTokenFile()); err == nil && len(b) > 0 {
		opts["restore_token"] = dbus.MakeVariant(strings.TrimSpace(string(b)))
	}
	if _, err := portalRequest(c, func(token string) (dbus.ObjectPath, error) {
		opts["handle_token"] = dbus.MakeVariant(token)
		var req dbus.ObjectPath
		err := rd.Call(portalRD+".SelectDevices", 0, sess, opts).Store(&req)
		return req, err
	}); err != nil {
		c.Object(portalDest, sess).Call(portalSess+".Close", 0)
		return err
	}
	res, err = portalRequest(c, func(token string) (dbus.ObjectPath, error) {
		var req dbus.ObjectPath
		err := rd.Call(portalRD+".Start", 0, sess, "", map[string]dbus.Variant{
			"handle_token": dbus.MakeVariant(token),
		}).Store(&req)
		return req, err
	})
	if err != nil {
		c.Object(portalDest, sess).Call(portalSess+".Close", 0)
		return err
	}
	if v, ok := res["restore_token"]; ok {
		if t, _ := v.Value().(string); t != "" {
			os.WriteFile(inputTokenFile(), []byte(t), 0o600)
		}
	}
	remoteInput.Lock()
	remoteInput.session = sess
	remoteInput.last = time.Now()
	remoteInput.Unlock()
	return nil
}

// portalRequest runs one portal call that answers through a Request
// object's Response signal, and returns the results.
func portalRequest(c *dbus.Conn, call func(token string) (dbus.ObjectPath, error)) (map[string]dbus.Variant, error) {
	inputStarting.n++
	token := fmt.Sprintf("palt%d_%d", os.Getpid(), inputStarting.n)
	// Listen on the path the portal will use before calling, so a fast
	// answer isn't missed.
	sender := strings.ReplaceAll(strings.TrimPrefix(c.Names()[0], ":"), ".", "_")
	path := dbus.ObjectPath(portalPath + "/request/" + sender + "/" + token)
	match := []dbus.MatchOption{dbus.WithMatchObjectPath(path), dbus.WithMatchInterface(portalReq), dbus.WithMatchMember("Response")}
	if err := c.AddMatchSignal(match...); err != nil {
		return nil, err
	}
	defer c.RemoveMatchSignal(match...)
	ch := make(chan *dbus.Signal, 4)
	inputResponses.Store(path, ch)
	defer inputResponses.Delete(path)

	got, err := call(token)
	if err != nil {
		return nil, err
	}
	if got != path {
		// Older portals pick their own path; follow it.
		inputResponses.Store(got, ch)
		defer inputResponses.Delete(got)
		m := []dbus.MatchOption{dbus.WithMatchObjectPath(got), dbus.WithMatchInterface(portalReq), dbus.WithMatchMember("Response")}
		c.AddMatchSignal(m...)
		defer c.RemoveMatchSignal(m...)
	}
	select {
	case s := <-ch:
		var code uint32
		var res map[string]dbus.Variant
		if err := dbus.Store(s.Body, &code, &res); err != nil {
			return nil, err
		}
		if code != 0 {
			return nil, errInputDenied
		}
		return res, nil
	case <-time.After(portalAsk):
		return nil, errors.New("no answer on the computer")
	}
}

var inputResponses sync.Map // request path → chan *dbus.Signal

func watchInputSignals(ch <-chan *dbus.Signal) {
	for s := range ch {
		switch s.Name {
		case portalReq + ".Response":
			if v, ok := inputResponses.Load(s.Path); ok {
				select {
				case v.(chan *dbus.Signal) <- s:
				default:
				}
			}
		case portalSess + ".Closed":
			remoteInput.Lock()
			if remoteInput.session == s.Path {
				remoteInput.session = ""
			}
			remoteInput.Unlock()
		}
	}
}

func closeIdleInput() {
	for range time.Tick(30 * time.Second) {
		remoteInput.Lock()
		if remoteInput.session != "" && time.Since(remoteInput.last) > inputIdle {
			stopInputLocked()
		}
		remoteInput.Unlock()
	}
}

// stopInput ends the session, which also clears GNOME's "being controlled"
// indicator. The saved permission stays.
func stopInput() {
	remoteInput.Lock()
	defer remoteInput.Unlock()
	stopInputLocked()
}

func stopInputLocked() {
	if remoteInput.session == "" {
		return
	}
	remoteInput.conn.Object(portalDest, remoteInput.session).Call(portalSess+".Close", 0)
	remoteInput.session = ""
}

// inputNotify sends one event without waiting for an answer, so a stream
// of pointer moves stays smooth. Fails when there is no session.
func inputNotify(method string, args ...any) error {
	remoteInput.Lock()
	defer remoteInput.Unlock()
	if remoteInput.session == "" {
		return errInputStopped
	}
	remoteInput.last = time.Now()
	all := append([]any{remoteInput.session, map[string]dbus.Variant{}}, args...)
	remoteInput.conn.Object(portalDest, portalPath).Go(portalRD+"."+method, dbus.FlagNoReplyExpected, nil, all...)
	return nil
}

func inputMove(dx, dy float64) error { return inputNotify("NotifyPointerMotion", dx, dy) }

func inputButton(button string, down bool) error {
	code := map[string]int32{"left": evdevLeft, "right": evdevRight, "middle": evdevMiddle}[button]
	if code == 0 {
		return errors.New("unknown button")
	}
	state := uint32(0)
	if down {
		state = 1
	}
	return inputNotify("NotifyPointerButton", code, state)
}

// inputScroll scrolls smoothly; finish ends the gesture so kinetic
// scrolling can take over.
func inputScroll(dx, dy float64, finish bool) error {
	remoteInput.Lock()
	defer remoteInput.Unlock()
	if remoteInput.session == "" {
		return errInputStopped
	}
	remoteInput.last = time.Now()
	remoteInput.conn.Object(portalDest, portalPath).Go(portalRD+".NotifyPointerAxis", dbus.FlagNoReplyExpected, nil,
		remoteInput.session, map[string]dbus.Variant{"finish": dbus.MakeVariant(finish)}, dx, dy)
	return nil
}

func inputKeysym(sym uint32, down bool) error {
	state := uint32(0)
	if down {
		state = 1
	}
	return inputNotify("NotifyKeyboardKeysym", int32(sym), state)
}
