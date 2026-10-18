//go:build !linux && !darwin

package main

func systemVolume() SystemVolume { return SystemVolume{Level: -1} }

func setSystemVolume(string, int) error { return errUnknownAction }

func watchVolume(func()) {}
