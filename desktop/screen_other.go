//go:build !linux

package main

import "errors"

var errScreenUnsupported = errors.New("screen capture needs Linux")

func screenSupported() bool                  { return false }
func takeScreenshot(string, bool) error      { return errScreenUnsupported }
func startScreencast(string) (string, error) { return "", errScreenUnsupported }
func stopScreencast() error                  { return errScreenUnsupported }
