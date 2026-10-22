// clipboard_linux.go talks to the PALT clipboard helper (a small GNOME Shell
// extension, packaging/palt-clipboard@palt): GNOME only lets the focused
// app use the clipboard, so the shell watches and sets it for PALT.
package main

import (
	"embed"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/godbus/dbus/v5"
)

const (
	clipHelperUUID = "palt-clipboard@palt"
	clipBusName    = "org.palt.Clipboard"
	clipPath       = "/org/palt/Clipboard"
)

//go:embed packaging/palt-clipboard@palt/*
var clipHelperFiles embed.FS

// clipboardHelperRunning reports whether the helper extension is active.
func clipboardHelperRunning() bool {
	conn, err := dbus.SessionBus()
	if err != nil {
		return false
	}
	var owned bool
	err = conn.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, clipBusName).Store(&owned)
	return err == nil && owned
}

// clipboardHelperInstalled reports whether the extension files exist,
// for the user or system-wide.
func clipboardHelperInstalled() bool {
	dirs := []string{"/usr/share/gnome-shell/extensions"}
	if d, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, filepath.Join(d, ".local/share/gnome-shell/extensions"))
	}
	for _, d := range dirs {
		if _, err := os.Stat(filepath.Join(d, clipHelperUUID, "metadata.json")); err == nil {
			return true
		}
	}
	return false
}

// installClipboardHelper puts the extension in the user's extensions and
// enables it. GNOME on Wayland loads new extensions at the next login.
func installClipboardHelper() error {
	if !clipboardHelperInstalled() {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		dir := filepath.Join(home, ".local/share/gnome-shell/extensions", clipHelperUUID)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		for _, name := range []string{"metadata.json", "extension.js"} {
			data, err := clipHelperFiles.ReadFile("packaging/palt-clipboard@palt/" + name)
			if err != nil {
				return err
			}
			if err := os.WriteFile(filepath.Join(dir, name), data, 0o644); err != nil {
				return err
			}
		}
	}
	// Turning user extensions on is a GNOME setting; enabling ours adds it
	// to the enabled list (takes effect once the shell has loaded it).
	exec.Command("gsettings", "set", "org.gnome.shell", "disable-user-extensions", "false").Run()
	if exec.Command("gnome-extensions", "enable", clipHelperUUID).Run() == nil {
		return nil
	}
	// The shell only learns about a new extension at login, and until then
	// gnome-extensions refuses to enable it, so add it to the list directly.
	return enableExtensionAtLogin(clipHelperUUID)
}

// refreshClipboardHelper rewrites the user's copy of the helper when this
// version of PALT ships a newer one. GNOME loads it at the next login.
func refreshClipboardHelper() {
	home, err := os.UserHomeDir()
	if err != nil {
		return
	}
	dir := filepath.Join(home, ".local/share/gnome-shell/extensions", clipHelperUUID)
	if _, err := os.Stat(dir); err != nil {
		return
	}
	for _, name := range []string{"metadata.json", "extension.js"} {
		data, err := clipHelperFiles.ReadFile("packaging/palt-clipboard@palt/" + name)
		if err != nil {
			return
		}
		path := filepath.Join(dir, name)
		if old, err := os.ReadFile(path); err == nil && string(old) == string(data) {
			continue
		}
		os.WriteFile(path, data, 0o644)
	}
}

// enableExtensionAtLogin adds uuid to GNOME's enabled-extensions list.
func enableExtensionAtLogin(uuid string) error {
	out, err := exec.Command("gsettings", "get", "org.gnome.shell", "enabled-extensions").Output()
	if err != nil {
		return err
	}
	list := strings.TrimSpace(string(out))
	if strings.Contains(list, "'"+uuid+"'") {
		return nil
	}
	list = strings.TrimSuffix(strings.TrimPrefix(list, "@as "), "]")
	if strings.TrimSpace(list) == "[" {
		list = "['" + uuid + "']"
	} else {
		list += ", '" + uuid + "']"
	}
	return exec.Command("gsettings", "set", "org.gnome.shell", "enabled-extensions", list).Run()
}

// watchClipboard calls onChange with each new clipboard text.
func watchClipboard(onChange func(text string)) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return
	}
	conn.AddMatchSignal(dbus.WithMatchInterface(clipBusName), dbus.WithMatchObjectPath(clipPath))
	ch := make(chan *dbus.Signal, 16)
	conn.Signal(ch)
	go func() {
		for s := range ch {
			if s.Name == clipBusName+".Changed" && len(s.Body) == 1 {
				if text, ok := s.Body[0].(string); ok {
					onChange(text)
				}
			}
		}
	}()
}

// setClipboardViaHelper sets the clipboard through the helper; false when
// the helper isn't running.
func setClipboardViaHelper(text string) bool {
	conn, err := dbus.SessionBus()
	if err != nil {
		return false
	}
	return conn.Object(clipBusName, clipPath).Call(clipBusName+".SetText", 0, text).Err == nil
}
