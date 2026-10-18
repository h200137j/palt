// main.go is the Wails entrypoint for PALT.
//
// Structure matches the established pattern used in this workspace
// (see tardis/main.go). Key points:
//   - The //go:embed directive bundles the compiled React frontend.
//   - linux.Options sets GPU policy to OnDemand (avoids crashes on some GPUs).
//   - Bind: []interface{}{app} exposes all exported App methods to the frontend.
package main

import (
	"context"
	"embed"
	"os"
	"slices"
	"time"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/linux"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
)

// assets embeds the compiled React frontend into the Go binary so the final
// .deb / binary is fully self-contained with no external web server.
//
//go:embed all:frontend/dist
var assets embed.FS

// instanceID names the single-instance lock shared by every PALT launch.
const instanceID = "com.lads.palt.desktop"

func main() {
	if !generatingBindings && signalRunningInstance(instanceID) {
		return
	}
	app := NewApp()

	// With a tray to come back from, closing the window keeps PALT running,
	// and the login entry starts it straight in the tray.
	cliCommand := len(os.Args) > 1 && (os.Args[1] == "--send" || os.Args[1] == "--ring")
	wantHidden := slices.Contains(os.Args[1:], startHiddenFlag) || cliCommand
	if wantHidden {
		app.trayEnabled = waitForTray(30 * time.Second)
	} else {
		app.trayEnabled = trayAvailable()
	}
	startHidden := app.trayEnabled && wantHidden
	app.windowHidden.Store(startHidden)

	err := wails.Run(&options.App{
		Title:     "PALT — Local File Transfer",
		Width:     1375,
		Height:    900,
		MinWidth:  800,
		MinHeight: 560,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		// Deep ink — matches Beacon background.default in theme.ts
		BackgroundColour: &options.RGBA{R: 12, G: 18, B: 32, A: 1},
		OnStartup:        app.startup,
		OnShutdown:       app.shutdown,
		// Not StartHidden: on Linux a window started hidden stays blank
		// when shown later. Hide it once the page has loaded instead.
		OnDomReady: func(ctx context.Context) {
			if startHidden && app.windowHidden.Load() {
				app.hideWindow()
			}
		},
		// With a tray, closing the window only hides it.
		OnBeforeClose: func(ctx context.Context) bool {
			if app.trayEnabled && !app.quitting.Load() {
				app.hideWindow()
				return true
			}
			return false
		},
		// Launching PALT again (or from the menu while it sits in the tray)
		// brings up the running window instead of fighting it for the port.
		SingleInstanceLock: &options.SingleInstanceLock{
			UniqueId: instanceID,
			OnSecondInstanceLaunch: func(d options.SecondInstanceData) {
				if len(d.Args) > 0 && (d.Args[0] == "--send" || d.Args[0] == "--ring") {
					app.handleArgs(d.Args, d.WorkingDirectory)
					return
				}
				app.showWindow()
			},
		},
		Menu: appMenu(),
		DragAndDrop: &options.DragAndDrop{
			EnableFileDrop: true,
		},
		Bind: []interface{}{
			app,
		},
		Linux: &linux.Options{
			WindowIsTranslucent: false,
			WebviewGpuPolicy:    linux.WebviewGpuPolicyOnDemand,
		},
		Mac: &mac.Options{
			About: &mac.AboutInfo{
				Title:   "PALT",
				Message: "Peer And Local Transfer\n" + AppVersion,
			},
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
