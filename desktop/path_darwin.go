// path_darwin.go estimates how fast this computer can reach a LAN address,
// so links (and the transfers that follow them) take the faster path.
package main

import "net"

// pathKind names how an address is reached: "wifi" or "lan".
func pathKind(ip string) string {
	if ifc := ifaceFor(ip); ifc != "" && isWirelessIface(ifc) {
		return "wifi"
	}
	return "lan"
}

// pathSpeed is a rough usable speed in Mbit/s to ip, at least 1. macOS
// doesn't report link rates without private APIs, so these are typical.
func pathSpeed(ip string) int {
	ifc := ifaceFor(ip)
	switch {
	case ifc == "":
		return 50
	case isWirelessIface(ifc):
		// Device to device every byte crosses the air twice.
		return 100
	}
	return 900
}

// ifaceFor returns the local interface on the same subnet as ip.
func ifaceFor(ip string) string {
	addr := net.ParseIP(ip)
	if addr == nil {
		return ""
	}
	ifaces, _ := net.Interfaces()
	for _, ifc := range ifaces {
		addrs, _ := ifc.Addrs()
		for _, a := range addrs {
			if n, ok := a.(*net.IPNet); ok && n.Contains(addr) {
				return ifc.Name
			}
		}
	}
	return ""
}
