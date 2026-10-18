// volume_darwin.go reads and sets this computer's output volume through
// AppleScript, for the media remote on paired phones.
package main

import (
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// systemVolume returns the output volume (0-100, -1 unknown).
func systemVolume() SystemVolume {
	v := SystemVolume{Level: -1}
	out, err := exec.Command("osascript", "-e",
		`set s to get volume settings
return (output volume of s as text) & "," & (output muted of s as text)`).Output()
	if err != nil {
		return v
	}
	level, muted, _ := strings.Cut(strings.TrimSpace(string(out)), ",")
	if n, err := strconv.Atoi(level); err == nil {
		v.Level = n
	}
	v.Muted = muted == "true"
	return v
}

// setSystemVolume sets the level (0-100), or toggles mute. Phones send
// "volume" (media.action); "level" is kept for older callers.
func setSystemVolume(action string, level int) error {
	switch action {
	case "volume", "level":
		level = max(0, min(level, 100))
		return exec.Command("osascript", "-e", "set volume output volume "+strconv.Itoa(level)).Run()
	case "mute":
		return exec.Command("osascript", "-e",
			`set volume output muted (not (output muted of (get volume settings)))`).Run()
	}
	return errUnknownAction
}

// watchVolume calls onChange when the volume or mute changes. macOS has no
// command-line way to subscribe, so it polls.
func watchVolume(onChange func()) {
	go func() {
		last := systemVolume()
		for range time.Tick(2 * time.Second) {
			if v := systemVolume(); v != last {
				last = v
				onChange()
			}
		}
	}()
}
