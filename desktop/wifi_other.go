//go:build !linux && !darwin

package main

import (
	"fmt"

	"palt/internal/wifiqr"
)

func currentWifi() (wifiqr.Network, error) {
	return wifiqr.Network{}, fmt.Errorf("sharing Wi-Fi is Linux-only for now")
}

func joinWifi(wifiqr.Network) error {
	return fmt.Errorf("joining Wi-Fi is Linux-only for now")
}
