// apps_app.go lets a paired phone act as an app dock for this computer: it
// lists the installed apps with their icons, opens one (or brings it
// forward when it is already open) and quits it.
//
// Packet types (must match mobile/lib/features/apps.dart):
//
//	apps.list     phone → desktop  {} → {apps: [{id, name, icon}], running: [id]}
//	                               icon changes whenever the picture does; "" none
//	apps.running  phone → desktop  {} → {running: [id]}
//	apps.icon     phone → desktop  {id} → {png}        base64 PNG, "" none
//	apps.launch   phone → desktop  {id} → {error?}
//	apps.quit     phone → desktop  {id} → {error?}
//
// All are requests. Icons go one at a time so a long app list stays well
// under the link's packet limit; the phone caches them by icon version.
package main

import (
	"encoding/base64"
	"log"

	"palt/internal/link"
)

// DockApp is one app a phone can open.
type DockApp struct {
	ID   string `json:"id"`   // desktop file ID, e.g. org.gnome.Nautilus.desktop
	Name string `json:"name"` // in the computer's language
	Icon string `json:"icon"` // version of the icon, "" when it has none
}

func (a *App) setupApps() {
	if !appsSupported() {
		return
	}
	prepareApps()
	a.links.Handle("apps.list", func(l *link.Link, p link.Packet) {
		go func() {
			apps, err := listApps()
			if err != nil {
				log.Printf("[apps] list: %v", err)
				apps = []DockApp{}
			}
			l.SendID("apps.list.reply", p.ID, map[string]any{"apps": apps, "running": runningApps()})
		}()
	})
	a.links.Handle("apps.running", func(l *link.Link, p link.Packet) {
		go l.SendID("apps.running.reply", p.ID, map[string]any{"running": runningApps()})
	})
	a.links.Handle("apps.icon", func(l *link.Link, p link.Packet) {
		var b struct{ ID string }
		if p.Decode(&b) != nil {
			return
		}
		go func() {
			png, _ := appIcon(b.ID)
			l.SendID("apps.icon.reply", p.ID, map[string]string{"png": base64.StdEncoding.EncodeToString(png)})
		}()
	})
	reply := func(t string, do func(string) error) link.Handler {
		return func(l *link.Link, p link.Packet) {
			var b struct{ ID string }
			if p.Decode(&b) != nil {
				return
			}
			go func() {
				r := map[string]string{}
				if err := do(b.ID); err != nil {
					log.Printf("[apps] %s %s: %v", t, b.ID, err)
					r["error"] = err.Error()
				}
				l.SendID(t+".reply", p.ID, r)
			}()
		}
	}
	a.links.Handle("apps.launch", reply("apps.launch", launchApp))
	a.links.Handle("apps.quit", reply("apps.quit", quitApp))
}
