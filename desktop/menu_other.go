//go:build !darwin

package main

import "github.com/wailsapp/wails/v2/pkg/menu"

// appMenu: no menu bar outside macOS.
func appMenu() *menu.Menu { return nil }
