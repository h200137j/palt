// wifi_darwin.go reads and joins Wi-Fi networks with networksetup, and
// reads saved passwords from the keychain (macOS asks the user first).
package main

import (
	"fmt"
	"os/exec"
	"strings"

	"palt/internal/wifiqr"
)

// currentWifi returns the Wi-Fi network this computer is on, with its
// password.
func currentWifi() (wifiqr.Network, error) {
	dev := wifiDevice()
	if dev == "" {
		return wifiqr.Network{}, fmt.Errorf("this computer has no Wi-Fi")
	}
	ssid := currentSSID(dev)
	if ssid == "" {
		return wifiqr.Network{}, fmt.Errorf("this computer isn't on Wi-Fi, or macOS is hiding the network name (allow PALT Location access)")
	}
	n := wifiqr.Network{SSID: ssid, Security: "WPA"}
	out, err := exec.Command("security", "find-generic-password",
		"-D", "AirPort network password", "-a", ssid, "-w").Output()
	if err != nil {
		return wifiqr.Network{}, fmt.Errorf("couldn't read the password for %s", ssid)
	}
	n.Password = strings.TrimRight(string(out), "\n")
	if n.Password == "" {
		n.Security = "nopass"
	}
	return n, nil
}

// joinWifi connects to a network; macOS saves it for next time.
func joinWifi(n wifiqr.Network) error {
	dev := wifiDevice()
	if dev == "" {
		return fmt.Errorf("this computer has no Wi-Fi")
	}
	args := []string{"-setairportnetwork", dev, n.SSID}
	if n.Security != "nopass" && n.Password != "" {
		args = append(args, n.Password)
	}
	out, err := exec.Command("networksetup", args...).CombinedOutput()
	// networksetup reports most failures on stdout with a zero exit.
	msg := strings.TrimSpace(string(out))
	if err != nil || msg != "" {
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("couldn't join %s: %s", n.SSID, msg)
	}
	return nil
}
