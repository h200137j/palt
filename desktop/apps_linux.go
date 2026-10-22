// apps_linux.go finds the installed apps from their .desktop files and their
// icons from the icon theme. Opening, quitting and knowing which apps are
// open go through the PALT helper extension (org.palt.Apps), because only
// GNOME Shell may raise a window; until it is loaded (it needs a login after
// installing), apps start with gio and open ones are guessed from /proc.
package main

import (
	"bufio"
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	"image/png"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/godbus/dbus/v5"
	"golang.org/x/image/draw"
)

const (
	appsBusName   = "org.palt.Apps"
	appsPath      = "/org/palt/Apps"
	iconSide      = 128 // pixels, square
	appsCacheFor  = 15 * time.Second
	iconsCacheFor = 5 * time.Minute
)

var errUnknownApp = errors.New("that app isn't installed")

type desktopApp struct {
	DockApp
	path    string // the .desktop file
	exec    string // binary name the app runs, for /proc matching
	wmClass string
	icon    string // resolved icon file, "" none
}

var apps struct {
	sync.Mutex
	list []desktopApp
	at   time.Time
}

func appsSupported() bool { return true }

func prepareApps() { go refreshClipboardHelper() }

// dataDirs are the XDG data directories, most important first.
func dataDirs() []string {
	var dirs []string
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		dirs = append(dirs, d)
	} else if h, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, filepath.Join(h, ".local/share"))
	}
	sys := os.Getenv("XDG_DATA_DIRS")
	if sys == "" {
		sys = "/usr/local/share:/usr/share"
	}
	for _, d := range strings.Split(sys, ":") {
		if d != "" && !slices.Contains(dirs, d) {
			dirs = append(dirs, d)
		}
	}
	return dirs
}

func loadApps() ([]desktopApp, error) {
	apps.Lock()
	defer apps.Unlock()
	if apps.list != nil && time.Since(apps.at) < appsCacheFor {
		return apps.list, nil
	}
	desktops := strings.Split(os.Getenv("XDG_CURRENT_DESKTOP"), ":")
	seen := map[string]bool{}
	var list []desktopApp
	for _, d := range dataDirs() {
		root := filepath.Join(d, "applications")
		filepath.WalkDir(root, func(path string, e fs.DirEntry, err error) error {
			if err != nil || e.IsDir() || !strings.HasSuffix(path, ".desktop") {
				return nil
			}
			rel, _ := filepath.Rel(root, path)
			id := strings.ReplaceAll(rel, "/", "-")
			if seen[id] {
				return nil
			}
			// An earlier directory's file wins, even a hidden one: that is how
			// users hide system apps.
			seen[id] = true
			if app, ok := parseDesktopFile(path, desktops); ok && id != "palt.desktop" {
				app.ID = id
				list = append(list, app)
			}
			return nil
		})
	}
	icons := iconFiles()
	for i := range list {
		list[i].icon = findIcon(icons, list[i].icon)
		list[i].Icon = iconVersion(list[i].icon)
	}
	slices.SortFunc(list, func(a, b desktopApp) int {
		return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
	})
	apps.list, apps.at = list, time.Now()
	return list, nil
}

// parseDesktopFile reads the [Desktop Entry] of an app that should be
// listed. On return, icon holds the Icon key, not yet resolved.
func parseDesktopFile(path string, desktops []string) (desktopApp, bool) {
	f, err := os.Open(path)
	if err != nil {
		return desktopApp{}, false
	}
	defer f.Close()
	keys := map[string]string{}
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, "[") {
			in = line == "[Desktop Entry]"
			continue
		}
		if k, v, ok := strings.Cut(line, "="); in && ok {
			k = strings.TrimSpace(k)
			if _, dup := keys[k]; !dup {
				keys[k] = strings.TrimSpace(v)
			}
		}
	}
	if keys["Type"] != "Application" || keys["NoDisplay"] == "true" || keys["Hidden"] == "true" || keys["Exec"] == "" {
		return desktopApp{}, false
	}
	shown := func(list string) bool {
		for _, d := range strings.Split(list, ";") {
			if d != "" && slices.Contains(desktops, d) {
				return true
			}
		}
		return false
	}
	if only := keys["OnlyShowIn"]; only != "" && !shown(only) {
		return desktopApp{}, false
	}
	if shown(keys["NotShowIn"]) {
		return desktopApp{}, false
	}
	if t := keys["TryExec"]; t != "" {
		if _, err := exec.LookPath(t); err != nil {
			return desktopApp{}, false
		}
	}
	name := keys["Name"]
	if lang, _, _ := strings.Cut(os.Getenv("LANG"), "."); lang != "" {
		short, _, _ := strings.Cut(lang, "_")
		for _, l := range []string{lang, short} {
			if n := keys["Name["+l+"]"]; n != "" {
				name = n
				break
			}
		}
	}
	if name == "" {
		return desktopApp{}, false
	}
	return desktopApp{
		DockApp: DockApp{Name: name},
		path:    path,
		exec:    execName(keys["Exec"]),
		wmClass: strings.ToLower(keys["StartupWMClass"]),
		icon:    keys["Icon"],
	}, true
}

// genericExecs run something else, so their name says nothing about the app.
var genericExecs = map[string]bool{
	"env": true, "sh": true, "bash": true, "python": true, "python3": true, "java": true,
	"flatpak": true, "snap": true, "gjs": true, "node": true, "electron": true, "wine": true,
}

// execName is the binary an Exec line runs, "" when it says nothing useful.
func execName(line string) string {
	first := ""
	if rest, ok := strings.CutPrefix(strings.TrimSpace(line), `"`); ok {
		first, _, _ = strings.Cut(rest, `"`)
	} else if fields := strings.Fields(line); len(fields) > 0 {
		first = fields[0]
	}
	if first == "" {
		return ""
	}
	name := filepath.Base(first)
	if genericExecs[name] {
		return ""
	}
	return name
}

func findApp(id string) (desktopApp, bool) {
	list, _ := loadApps()
	for _, a := range list {
		if a.ID == id {
			return a, true
		}
	}
	return desktopApp{}, false
}

func listApps() ([]DockApp, error) {
	list, err := loadApps()
	out := make([]DockApp, len(list))
	for i, a := range list {
		out[i] = a.DockApp
	}
	return out, err
}

// ── Open apps ────────────────────────────────────────────────────────────────

// shellApps is the helper extension's object, or nil when it isn't running.
func shellApps() dbus.BusObject {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil
	}
	var owned bool
	if conn.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, appsBusName).Store(&owned) != nil || !owned {
		return nil
	}
	return conn.Object(appsBusName, appsPath)
}

func runningApps() []string {
	if o := shellApps(); o != nil {
		var ids []string
		if o.Call(appsBusName+".Running", 0).Store(&ids) == nil {
			return ids
		}
	}
	ids := []string{}
	for id := range guessRunning() {
		ids = append(ids, id)
	}
	slices.Sort(ids)
	return ids
}

var (
	gnomeScope = regexp.MustCompile(`^app-[a-z0-9]+-(.+)-[0-9]+\.scope$`)
	snapScope  = regexp.MustCompile(`^snap\.([^.]+)\.([^.]+?)-[0-9a-f]{8}-[0-9a-f-]+\.scope$`)
)

// unescapeUnit undoes systemd's \xNN escaping in unit names.
func unescapeUnit(s string) string {
	if !strings.Contains(s, `\x`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if i+3 < len(s) && s[i] == '\\' && s[i+1] == 'x' {
			if n, err := strconv.ParseUint(s[i+2:i+4], 16, 8); err == nil {
				b.WriteByte(byte(n))
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// guessRunning maps the installed apps that seem to be open to their
// processes: GNOME starts each app in a systemd scope named after it, and
// apps started otherwise are matched by the binary they run.
func guessRunning() map[string][]int {
	list, _ := loadApps()
	byID := map[string]bool{}
	byExec := map[string]string{}
	for _, a := range list {
		byID[a.ID] = true
		for _, n := range []string{a.exec, a.wmClass} {
			if n != "" {
				byExec[n] = a.ID
			}
		}
	}
	me := os.Getuid()
	out := map[string][]int{}
	entries, _ := os.ReadDir("/proc")
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		dir := "/proc/" + e.Name()
		if st, err := os.Stat(dir); err != nil || int(st.Sys().(*syscall.Stat_t).Uid) != me {
			continue
		}
		id := ""
		if cg, err := os.ReadFile(dir + "/cgroup"); err == nil {
			unit := filepath.Base(strings.TrimSpace(string(cg)))
			if m := gnomeScope.FindStringSubmatch(unit); m != nil {
				id = unescapeUnit(m[1]) + ".desktop"
			} else if m := snapScope.FindStringSubmatch(unit); m != nil {
				id = m[1] + "_" + m[2] + ".desktop"
			}
		}
		if !byID[id] {
			id = ""
			if exe, err := os.Readlink(dir + "/exe"); err == nil {
				id = byExec[filepath.Base(exe)]
			}
		}
		if id != "" {
			out[id] = append(out[id], pid)
		}
	}
	return out
}

func launchApp(id string) error {
	if o := shellApps(); o != nil {
		var ok bool
		if err := o.Call(appsBusName+".Activate", 0, id).Store(&ok); err == nil {
			if !ok {
				return errUnknownApp
			}
			return nil
		}
	}
	app, ok := findApp(id)
	if !ok {
		return errUnknownApp
	}
	cmd := exec.Command("gio", "launch", app.path)
	if _, err := exec.LookPath("gio"); err != nil {
		cmd = exec.Command("gtk-launch", strings.TrimSuffix(id, ".desktop"))
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	// gio returns once the app has started; a failure shows up quickly.
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			if msg := strings.TrimSpace(stderr.String()); msg != "" {
				return errors.New(msg)
			}
			return err
		}
	case <-time.After(3 * time.Second):
	}
	return nil
}

func quitApp(id string) error {
	if o := shellApps(); o != nil {
		var ok bool
		if err := o.Call(appsBusName+".Quit", 0, id).Store(&ok); err == nil {
			if !ok {
				return errors.New("that app isn't open")
			}
			return nil
		}
	}
	pids := guessRunning()[id]
	if len(pids) == 0 {
		return errors.New("that app isn't open")
	}
	for _, pid := range pids {
		syscall.Kill(pid, syscall.SIGTERM)
	}
	return nil
}

// ── Icons ────────────────────────────────────────────────────────────────────

type themeIcon struct {
	path  string
	size  int // pixels; scalable counts as 512
	theme int // position in the theme chain, lower wins
}

var icons struct {
	sync.Mutex
	files map[string]themeIcon // icon name → best file
	at    time.Time
	png   map[string][]byte // rendered, by file path and version
}

func iconTheme() string {
	out, err := exec.Command("gsettings", "get", "org.gnome.desktop.interface", "icon-theme").Output()
	if err == nil {
		if t := strings.Trim(strings.TrimSpace(string(out)), "'"); t != "" {
			return t
		}
	}
	return "Adwaita"
}

// themeChain is the icon theme followed by the themes it inherits from,
// ending with hicolor.
func themeChain(roots []string) []string {
	chain := []string{}
	var add func(string)
	add = func(t string) {
		if t == "" || slices.Contains(chain, t) || len(chain) > 8 {
			return
		}
		chain = append(chain, t)
		for _, r := range roots {
			b, err := os.ReadFile(filepath.Join(r, t, "index.theme"))
			if err != nil {
				continue
			}
			for _, line := range strings.Split(string(b), "\n") {
				if v, ok := strings.CutPrefix(strings.TrimSpace(line), "Inherits="); ok {
					for _, p := range strings.Split(v, ",") {
						add(strings.TrimSpace(p))
					}
				}
			}
			break
		}
	}
	add(iconTheme())
	add("Adwaita")
	add("hicolor")
	return chain
}

// iconSize reads the size from a theme path like .../256x256/apps/x.png or
// .../apps/48/x.svg.
var sizeDir = regexp.MustCompile(`^([0-9]+)(?:x[0-9]+)?(?:@([0-9])x?)?$`)

func iconSize(path string) int {
	size := 0
	for _, part := range strings.Split(path, "/") {
		if part == "scalable" {
			return 512
		}
		if m := sizeDir.FindStringSubmatch(part); m != nil {
			size, _ = strconv.Atoi(m[1])
			if m[2] != "" {
				scale, _ := strconv.Atoi(m[2])
				size *= scale
			}
		}
	}
	return size
}

// better reports whether a is a better icon than b: big enough beats tiny,
// then the theme the user picked beats the fallbacks, then bigger wins.
func (a themeIcon) better(b themeIcon) bool {
	if ag, bg := a.size >= 64, b.size >= 64; ag != bg {
		return ag
	}
	if a.theme != b.theme {
		return a.theme < b.theme
	}
	return a.size > b.size
}

// iconFiles indexes the app icons of the theme chain and pixmaps.
func iconFiles() map[string]themeIcon {
	icons.Lock()
	defer icons.Unlock()
	if icons.files != nil && time.Since(icons.at) < iconsCacheFor {
		return icons.files
	}
	var roots []string
	if h, err := os.UserHomeDir(); err == nil {
		roots = append(roots, filepath.Join(h, ".icons"))
	}
	for _, d := range dataDirs() {
		roots = append(roots, filepath.Join(d, "icons"))
	}
	files := map[string]themeIcon{}
	consider := func(path string, f themeIcon) {
		ext := filepath.Ext(path)
		if ext != ".png" && ext != ".svg" {
			return
		}
		name := strings.TrimSuffix(filepath.Base(path), ext)
		if strings.HasSuffix(name, "-symbolic") {
			return
		}
		f.path = path
		if old, ok := files[name]; !ok || f.better(old) {
			files[name] = f
		}
	}
	for rank, theme := range themeChain(roots) {
		for _, r := range roots {
			filepath.WalkDir(filepath.Join(r, theme), func(path string, e fs.DirEntry, err error) error {
				if err != nil || e.IsDir() {
					return nil
				}
				if strings.Contains(path, "/symbolic/") || strings.Contains(path, "/mimetypes/") {
					return nil
				}
				consider(path, themeIcon{size: iconSize(path), theme: rank})
				return nil
			})
		}
	}
	for _, d := range dataDirs() {
		entries, _ := os.ReadDir(filepath.Join(d, "pixmaps"))
		for _, e := range entries {
			consider(filepath.Join(d, "pixmaps", e.Name()), themeIcon{size: 48, theme: 100})
		}
	}
	icons.files, icons.at = files, time.Now()
	return files
}

// findIcon resolves a desktop file's Icon key to a file, "" if none.
func findIcon(files map[string]themeIcon, key string) string {
	if key == "" {
		return ""
	}
	if filepath.IsAbs(key) {
		if _, err := os.Stat(key); err == nil {
			return key
		}
		// A path into a package that moved (snaps); try the theme.
		key = filepath.Base(key)
	}
	key = strings.TrimSuffix(strings.TrimSuffix(key, ".png"), ".svg")
	return files[key].path
}

// iconVersion changes when the icon file does.
func iconVersion(path string) string {
	if path == "" {
		return ""
	}
	st, err := os.Stat(path)
	if err != nil {
		return ""
	}
	h := sha1.Sum([]byte(fmt.Sprintf("%s|%d|%d", path, st.Size(), st.ModTime().UnixNano())))
	return hex.EncodeToString(h[:6])
}

// appIcon renders the app's icon as an iconSide PNG.
func appIcon(id string) ([]byte, error) {
	app, ok := findApp(id)
	if !ok {
		return nil, errUnknownApp
	}
	if app.icon == "" {
		return nil, nil
	}
	key := app.icon + "|" + app.Icon
	icons.Lock()
	cached, ok := icons.png[key]
	icons.Unlock()
	if ok {
		return cached, nil
	}
	var out []byte
	var err error
	if strings.HasSuffix(app.icon, ".svg") {
		side := strconv.Itoa(iconSide)
		out, err = exec.Command("rsvg-convert", "-w", side, "-h", side, "--keep-aspect-ratio", app.icon).Output()
	} else {
		out, err = scaleIcon(app.icon)
	}
	if err != nil {
		return nil, err
	}
	icons.Lock()
	if icons.png == nil {
		icons.png = map[string][]byte{}
	}
	icons.png[key] = out
	icons.Unlock()
	return out, nil
}

// scaleIcon fits a picture into an iconSide square PNG.
func scaleIcon(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	src, _, err := image.Decode(f)
	if err != nil {
		return nil, err
	}
	b := src.Bounds()
	w, h := iconSide, iconSide
	if b.Dx() > b.Dy() {
		h = iconSide * b.Dy() / b.Dx()
	} else if b.Dy() > b.Dx() {
		w = iconSide * b.Dx() / b.Dy()
	}
	dst := image.NewNRGBA(image.Rect(0, 0, iconSide, iconSide))
	off := image.Pt((iconSide-w)/2, (iconSide-h)/2)
	draw.CatmullRom.Scale(dst, image.Rectangle{off, off.Add(image.Pt(w, h))}, src, b, draw.Over, nil)
	var buf bytes.Buffer
	if err := png.Encode(&buf, dst); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
