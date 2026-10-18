//go:build !linux && !darwin

package main

import "errors"

func setIdleInhibit(bool) error { return errors.New("not supported") }
