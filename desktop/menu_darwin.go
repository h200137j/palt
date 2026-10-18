// menu_darwin.go gives PALT the standard macOS menu bar. Without an Edit
// menu, Cmd+C, Cmd+V and friends do nothing in the window.
package main

import "github.com/wailsapp/wails/v2/pkg/menu"

func appMenu() *menu.Menu {
	m := menu.NewMenu()
	m.Append(menu.AppMenu())
	m.Append(menu.EditMenu())
	m.Append(menu.WindowMenu())
	return m
}
