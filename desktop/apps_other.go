//go:build !linux

package main

import "errors"

var errAppsUnsupported = errors.New("the app dock needs Linux")

func appsSupported() bool            { return false }
func prepareApps()                   {}
func listApps() ([]DockApp, error)   { return nil, errAppsUnsupported }
func runningApps() []string          { return []string{} }
func appIcon(string) ([]byte, error) { return nil, errAppsUnsupported }
func launchApp(string) error         { return errAppsUnsupported }
func quitApp(string) error           { return errAppsUnsupported }
