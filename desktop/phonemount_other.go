//go:build !linux

package main

func (a *App) setupPhoneMounts() {}

func unmountPhones() {}
