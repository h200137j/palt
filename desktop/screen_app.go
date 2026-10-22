// screen_app.go lets a paired phone take a screenshot of this computer or
// record its screen. Captures are saved here (Pictures/Screenshots,
// Videos/Screencasts); the phone sees a preview and can ask for the file.
//
// Packet types (all requests; must match mobile/lib/features/screen_capture.dart):
//
//	screen.shot    phone → desktop  {window?} → {path, name, preview?, error?}
//	                                window: just the focused window;
//	                                preview: base64 JPEG, at most 1280 px
//	screen.crop    phone → desktop  {path, x, y, w, h} → like screen.shot
//	                                crops a screenshot in place; the box is
//	                                in fractions (0-1) of the picture
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
	"image"
	"image/png"
	"log"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"palt/internal/link"
	"palt/internal/thumbs"
)

const (
	// maxRecording stops a recording someone forgot about.
	maxRecording = time.Hour
	// previewSide is big enough to choose a crop on a phone.
	previewSide = 1280
)

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
	shotReply := func(path string, err error) map[string]any {
		reply := map[string]any{}
		if err != nil {
			log.Printf("[screen] screenshot: %v", err)
			reply["error"] = err.Error()
			return reply
		}
		reply["path"], reply["name"] = path, filepath.Base(path)
		if b, err := os.ReadFile(path); err == nil {
			if jpg, err := thumbs.MakeSize(b, previewSide); err == nil {
				reply["preview"] = base64.StdEncoding.EncodeToString(jpg)
			}
		}
		return reply
	}
	a.links.Handle("screen.shot", func(l *link.Link, p link.Packet) {
		var b struct{ Window bool }
		p.Decode(&b)
		go func() {
			l.SendID("screen.shot.reply", p.ID, shotReply(a.screenshot(b.Window)))
		}()
	})
	a.links.Handle("screen.crop", func(l *link.Link, p link.Packet) {
		var b struct {
			Path       string
			X, Y, W, H float64
		}
		if p.Decode(&b) != nil {
			return
		}
		go func() {
			a.screen.mu.Lock()
			ok := a.screen.files[b.Path]
			a.screen.mu.Unlock()
			err := errNotACapture
			if ok {
				err = cropPNG(b.Path, b.X, b.Y, b.W, b.H)
			}
			l.SendID("screen.crop.reply", p.ID, shotReply(b.Path, err))
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

func (a *App) screenshot(window bool) (string, error) {
	dir := filepath.Join(userDir("PICTURES", "Pictures"), "Screenshots")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "Screenshot From "+time.Now().Format("2006-01-02 15-04-05")+".png")
	if err := takeScreenshot(path, window); err != nil {
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

// cropPNG cuts the picture at path down to a box given in fractions of its
// size, in place.
func cropPNG(path string, x, y, w, h float64) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	img, err := png.Decode(f)
	f.Close()
	if err != nil {
		return err
	}
	b := img.Bounds()
	clamp := func(v float64) float64 { return math.Max(0, math.Min(1, v)) }
	r := image.Rect(
		b.Min.X+int(clamp(x)*float64(b.Dx())), b.Min.Y+int(clamp(y)*float64(b.Dy())),
		b.Min.X+int(math.Ceil(clamp(x+w)*float64(b.Dx()))), b.Min.Y+int(math.Ceil(clamp(y+h)*float64(b.Dy()))),
	)
	if r.Dx() < 2 || r.Dy() < 2 {
		return errors.New("that area is too small")
	}
	sub, ok := img.(interface {
		SubImage(image.Rectangle) image.Image
	})
	if !ok {
		return errors.New("can't crop this picture")
	}
	tmp := path + ".crop"
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if err := png.Encode(out, sub.SubImage(r)); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}
