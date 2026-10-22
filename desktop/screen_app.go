// screen_app.go lets a paired phone take a screenshot of this computer or
// record its screen. Captures are saved here (Pictures/Screenshots,
// Videos/Screencasts); the phone sees a preview and can ask for the file.
//
// Packet types (all requests; must match mobile/lib/features/screen_capture.dart):
//
//	screen.shot    phone → desktop  {} → {path, name, preview?, error?}
//	                                preview: base64 JPEG, at most 480 px
//	screen.record  phone → desktop  {action: start|stop|status}
//	                                → {recording, since?, path?, error?}
//	                                since: start time, ms since the epoch;
//	                                path: the finished recording, after stop
//	screen.fetch   phone → desktop  {path} → {error?}  sends that capture to
//	                                the phone as an ordinary transfer
package main

import (
	"encoding/base64"
	"errors"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"palt/internal/link"
	"palt/internal/thumbs"
)

// maxRecording stops a recording someone forgot about.
const maxRecording = time.Hour

var errNotACapture = errors.New("that file isn't a capture from PALT")

type screenState struct {
	mu        sync.Mutex
	files     map[string]bool // captures the phone may fetch
	recording string          // template while recording, "" when not
	path      string          // file being recorded
	since     time.Time
	limit     *time.Timer
}

func (a *App) setupScreenCapture() {
	if !screenSupported() {
		return
	}
	a.screen.files = map[string]bool{}
	a.links.Handle("screen.shot", func(l *link.Link, p link.Packet) {
		go func() {
			reply := map[string]any{}
			path, err := a.screenshot()
			if err != nil {
				log.Printf("[screen] screenshot: %v", err)
				reply["error"] = err.Error()
			} else {
				reply["path"], reply["name"] = path, filepath.Base(path)
				if b, err := os.ReadFile(path); err == nil {
					if jpg, err := thumbs.Make(b); err == nil {
						reply["preview"] = base64.StdEncoding.EncodeToString(jpg)
					}
				}
			}
			l.SendID("screen.shot.reply", p.ID, reply)
		}()
	})
	a.links.Handle("screen.record", func(l *link.Link, p link.Packet) {
		var b struct{ Action string }
		if p.Decode(&b) != nil {
			return
		}
		go func() {
			reply := map[string]any{}
			var err error
			var done string
			switch b.Action {
			case "start":
				err = a.startRecording()
			case "stop":
				done, err = a.stopRecording()
			}
			if err != nil {
				log.Printf("[screen] %s recording: %v", b.Action, err)
				reply["error"] = err.Error()
			}
			a.screen.mu.Lock()
			reply["recording"] = a.screen.recording != ""
			if a.screen.recording != "" {
				reply["since"] = a.screen.since.UnixMilli()
			}
			a.screen.mu.Unlock()
			if done != "" {
				reply["path"] = done
				reply["name"] = filepath.Base(done)
			}
			l.SendID("screen.record.reply", p.ID, reply)
		}()
	})
	a.links.Handle("screen.fetch", func(l *link.Link, p link.Packet) {
		var b struct{ Path string }
		if p.Decode(&b) != nil {
			return
		}
		go func() {
			reply := map[string]any{}
			a.screen.mu.Lock()
			ok := a.screen.files[b.Path]
			a.screen.mu.Unlock()
			var err error
			if !ok {
				err = errNotACapture
			} else if _, err = os.Stat(b.Path); err == nil {
				err = a.sendPathsTo("", 0, l.Peer.Name, []string{b.Path}, "")
			}
			if err != nil {
				reply["error"] = err.Error()
			}
			l.SendID("screen.fetch.reply", p.ID, reply)
		}()
	})
}

func (a *App) screenshot() (string, error) {
	dir := filepath.Join(userDir("PICTURES", "Pictures"), "Screenshots")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "Screenshot From "+time.Now().Format("2006-01-02 15-04-05")+".png")
	if err := takeScreenshot(path); err != nil {
		os.Remove(path)
		return "", err
	}
	a.screen.mu.Lock()
	a.screen.files[path] = true
	a.screen.mu.Unlock()
	return path, nil
}

func (a *App) startRecording() error {
	a.screen.mu.Lock()
	defer a.screen.mu.Unlock()
	if a.screen.recording != "" {
		return nil
	}
	dir := filepath.Join(userDir("VIDEOS", "Videos"), "Screencasts")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	template := filepath.Join(dir, "Screencast From "+time.Now().Format("2006-01-02 15-04-05"))
	path, err := startScreencast(template)
	if err != nil {
		return err
	}
	a.screen.recording, a.screen.path, a.screen.since = template, path, time.Now()
	a.screen.limit = time.AfterFunc(maxRecording, func() {
		if p, err := a.stopRecording(); err == nil {
			log.Printf("[screen] stopped %s after %v", p, maxRecording)
		}
	})
	return nil
}

// stopRecording ends the recording and returns its file.
func (a *App) stopRecording() (string, error) {
	a.screen.mu.Lock()
	defer a.screen.mu.Unlock()
	if a.screen.recording == "" {
		return "", nil
	}
	a.screen.limit.Stop()
	path := a.screen.path
	a.screen.recording, a.screen.path = "", ""
	if err := stopScreencast(); err != nil {
		return "", err
	}
	a.screen.files[path] = true
	return path, nil
}

// userDir is an XDG user folder such as PICTURES, or ~/fallback.
func userDir(name, fallback string) string {
	home, _ := os.UserHomeDir()
	if out, err := exec.Command("xdg-user-dir", name).Output(); err == nil {
		if d := strings.TrimSpace(string(out)); d != "" && d != home {
			return d
		}
	}
	return filepath.Join(home, fallback)
}
