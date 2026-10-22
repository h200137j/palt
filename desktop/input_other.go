//go:build !linux

package main

import "errors"

var errInputUnsupported = errors.New("remote control needs Linux")

func startInput() error                        { return errInputUnsupported }
func stopInput()                               {}
func inputMove(float64, float64) error         { return errInputUnsupported }
func inputButton(string, bool) error           { return errInputUnsupported }
func inputScroll(float64, float64, bool) error { return errInputUnsupported }
func inputKeysym(uint32, bool) error           { return errInputUnsupported }

func watchTextFocus(func(editable, password bool)) {}
func stopTextFocus()                               {}
