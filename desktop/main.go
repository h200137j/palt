// main.go is the Wails entrypoint for PALT.
//
// Structure matches the established pattern used in this workspace
// (see tardis/main.go). Key points:
//   - The //go:embed directive bundles the compiled React frontend.
//   - linux.Options sets GPU policy to OnDemand (avoids crashes on some GPUs).
//   - Bind: []interface{}{app} exposes all exported App methods to the frontend.
package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/linux"
)

// assets embeds the compiled React frontend into the Go binary so the final
// .deb / binary is fully self-contained with no external web server.
//
//go:embed all:frontend/dist
var assets embed.FS

func main() {
	app := NewApp()

	err := wails.Run(&options.App{
		Title:     "PALT — Local File Transfer",
		Width:     1100,
		Height:    720,
		MinWidth:  800,
		MinHeight: 560,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		// Light grey — matches MUI background.default in theme.ts
		BackgroundColour: &options.RGBA{R: 248, G: 249, B: 250, A: 1},
		OnStartup:        app.startup,
		OnShutdown:       app.shutdown,
		Bind: []interface{}{
			app,
		},
		Linux: &linux.Options{
			WindowIsTranslucent: false,
			WebviewGpuPolicy:    linux.WebviewGpuPolicyOnDemand,
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
