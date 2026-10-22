package main

import (
	"os"
	"testing"
)

func TestExecName(t *testing.T) {
	for in, want := range map[string]string{
		"/usr/bin/firefox %u":      "firefox",
		`"/opt/My App/app" --flag`: "app",
		"env FOO=1 thing":          "",
		"python3 /usr/bin/tool.py": "",
		"":                         "",
	} {
		if got := execName(in); got != want {
			t.Errorf("execName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestUnescapeUnit(t *testing.T) {
	if got := unescapeUnit(`org.gnome.Evolution\x2dalarm\x2dnotify`); got != "org.gnome.Evolution-alarm-notify" {
		t.Fatal(got)
	}
	if m := gnomeScope.FindStringSubmatch(`app-gnome-github\x2ddesktop-51687.scope`); m == nil || unescapeUnit(m[1]) != "github-desktop" {
		t.Fatal(m)
	}
	if m := snapScope.FindStringSubmatch("snap.firefox.firefox-1b2c3d4e-aaaa-bbbb-cccc-0123456789ab.scope"); m == nil || m[1] != "firefox" || m[2] != "firefox" {
		t.Fatal(m)
	}
}

func TestIconSize(t *testing.T) {
	for in, want := range map[string]int{
		"/usr/share/icons/hicolor/256x256/apps/x.png":  256,
		"/usr/share/icons/Yaru/48x48@2x/apps/x.png":    96,
		"/usr/share/icons/hicolor/scalable/apps/x.svg": 512,
		"/usr/share/icons/Papirus/apps/48/x.svg":       48,
	} {
		if got := iconSize(in); got != want {
			t.Errorf("iconSize(%q) = %d, want %d", in, got, want)
		}
	}
}

func TestAtspiClassify(t *testing.T) {
	bits := func(list ...uint) []uint32 {
		w := make([]uint32, 2)
		for _, b := range list {
			w[b/32] |= 1 << (b % 32)
		}
		return w
	}
	cases := []struct {
		state              []uint32
		role               uint32
		editable, password bool
	}{
		{bits(atspiStateEditable, atspiStateEnabled, atspiStateSensitive), 79, true, false},
		{bits(atspiStateEditable, atspiStateEnabled, atspiStateReadOnly), 79, false, false},
		{bits(atspiStateEditable), 79, false, false},
		{bits(atspiStateEnabled), 43, false, false},
		{bits(atspiStateEnabled), atspiRolePassword, true, true},
		{bits(atspiStateEnabled), atspiRoleTerminal, true, false},
		{nil, 79, false, false},
	}
	for i, c := range cases {
		if e, p := atspiClassify(c.state, c.role); e != c.editable || p != c.password {
			t.Errorf("case %d: got %v %v", i, e, p)
		}
	}
}

// PALT_LIVE_APPS=1 go test -run Live -v lists this computer's apps.
func TestLiveApps(t *testing.T) {
	if os.Getenv("PALT_LIVE_APPS") == "" {
		t.Skip("set PALT_LIVE_APPS=1")
	}
	list, _ := listApps()
	noIcon := 0
	for _, a := range list {
		if a.Icon == "" {
			noIcon++
			t.Logf("no icon: %s (%s)", a.Name, a.ID)
		}
	}
	t.Logf("%d apps, %d without icons; running: %v", len(list), noIcon, runningApps())
	for _, a := range list[:min(5, len(list))] {
		png, err := appIcon(a.ID)
		t.Logf("%s icon: %d bytes, %v", a.Name, len(png), err)
	}
}
