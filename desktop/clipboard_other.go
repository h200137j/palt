//go:build !linux && !darwin

package main

func clipboardHelperRunning() bool      { return false }
func clipboardHelperInstalled() bool    { return false }
func installClipboardHelper() error     { return nil }
func watchClipboard(func(string))       {}
func setClipboardViaHelper(string) bool { return false }
