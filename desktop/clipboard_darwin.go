// clipboard_darwin.go: macOS lets background apps use the clipboard, so no
// helper is needed; PALT watches it with pbpaste and sets it with pbcopy.
package main

import (
	"os/exec"
	"strings"
	"time"
)

func clipboardHelperRunning() bool   { return true }
func clipboardHelperInstalled() bool { return true }
func installClipboardHelper() error  { return nil }

// watchClipboard calls onChange with each new clipboard text. There is no
// change notification for the pasteboard, so it polls.
func watchClipboard(onChange func(text string)) {
	go func() {
		last, _ := pasteboardText()
		for range time.Tick(time.Second) {
			text, err := pasteboardText()
			if err != nil || text == last {
				continue
			}
			last = text
			onChange(text)
		}
	}()
}

// setClipboardViaHelper sets the clipboard with pbcopy.
func setClipboardViaHelper(text string) bool {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	cmd.Env = append(cmd.Environ(), "LANG=en_US.UTF-8")
	return cmd.Run() == nil
}

func pasteboardText() (string, error) {
	cmd := exec.Command("pbpaste")
	cmd.Env = append(cmd.Environ(), "LANG=en_US.UTF-8")
	out, err := cmd.Output()
	return string(out), err
}
