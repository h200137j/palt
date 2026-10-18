// status_darwin.go reads this computer's battery (pmset) and network
// (route, networksetup, ipconfig) so paired devices can show them.
package main

import (
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

var battRe = regexp.MustCompile(`(\d+)%;\s*([a-z ]+);`)

func localStatus() DeviceStatus {
	st := DeviceStatus{Battery: -1, Signal: -1}
	if out, err := exec.Command("pmset", "-g", "batt").Output(); err == nil {
		if m := battRe.FindStringSubmatch(string(out)); m != nil {
			st.Battery, _ = strconv.Atoi(m[1])
			st.Charging = m[2] == "charging" || m[2] == "charged"
		}
	}

	ifc := defaultIface()
	if ifc == "" {
		return st
	}
	// A default route is the closest cheap sign of internet access.
	st.Internet = true
	if isWirelessIface(ifc) {
		st.Network = "wifi"
		st.SSID = currentSSID(ifc)
	} else {
		st.Network = "ethernet"
	}
	return st
}

// defaultIface is the interface carrying the default route, "" if none.
func defaultIface() string {
	out, err := exec.Command("route", "-n", "get", "default").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		if name, ok := strings.CutPrefix(strings.TrimSpace(line), "interface:"); ok {
			return strings.TrimSpace(name)
		}
	}
	return ""
}

// currentSSID is the Wi-Fi network ifc is on. Recent macOS redacts it
// unless the app has Location access; then it is "".
func currentSSID(ifc string) string {
	out, err := exec.Command("ipconfig", "getsummary", ifc).Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		if ssid, ok := strings.CutPrefix(strings.TrimSpace(line), "SSID : "); ok {
			if ssid == "<redacted>" {
				return ""
			}
			return ssid
		}
	}
	return ""
}

var hardwarePortCache struct {
	sync.Mutex
	at    time.Time
	ports map[string]string // device (en0) → hardware port (Wi-Fi)
}

// hardwarePorts maps network devices to their hardware port names.
func hardwarePorts() map[string]string {
	c := &hardwarePortCache
	c.Lock()
	defer c.Unlock()
	if c.ports != nil && time.Since(c.at) < time.Minute {
		return c.ports
	}
	c.at, c.ports = time.Now(), map[string]string{}
	out, err := exec.Command("networksetup", "-listallhardwareports").Output()
	if err != nil {
		return c.ports
	}
	port := ""
	for _, line := range strings.Split(string(out), "\n") {
		if p, ok := strings.CutPrefix(line, "Hardware Port: "); ok {
			port = p
		} else if d, ok := strings.CutPrefix(line, "Device: "); ok {
			c.ports[d] = port
		}
	}
	return c.ports
}

func isWirelessIface(name string) bool { return hardwarePorts()[name] == "Wi-Fi" }

// wifiDevice is the Wi-Fi interface name (usually en0), "" if none.
func wifiDevice() string {
	for dev, port := range hardwarePorts() {
		if port == "Wi-Fi" {
			return dev
		}
	}
	return ""
}
