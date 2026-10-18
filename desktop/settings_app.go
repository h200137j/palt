// settings_app.go keeps per-device feature switches ("show this phone's
// notifications", "sync clipboard", ...), keyed by device name.
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// Defaults for every switch; a device without saved settings gets these.
var deviceSettingDefaults = map[string]bool{
	"notifications":    true,  // show the device's notifications here
	"clipboardSend":    true,  // send this computer's clipboard to it
	"clipboardReceive": true,  // take its clipboard
	"pauseOnCall":      true,  // pause media when a call comes in
	"keepAwake":        false, // keep this computer from going idle while linked
	"proximityLock":    false, // lock this computer when the device goes away
	"mountFiles":       true,  // show a phone's storage as ~/PALT/<phone>
}

var settingsMu sync.Mutex

func deviceSettingsFile() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "device_settings.json")
}

func loadDeviceSettings() map[string]map[string]bool {
	all := map[string]map[string]bool{}
	if f := deviceSettingsFile(); f != "" {
		if data, err := os.ReadFile(f); err == nil {
			_ = json.Unmarshal(data, &all)
		}
	}
	return all
}

// setting reports a device's switch, falling back to the default.
func (a *App) setting(device, key string) bool {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	if v, ok := loadDeviceSettings()[device][key]; ok {
		return v
	}
	return deviceSettingDefaults[key]
}

// GetDeviceSettings returns every switch for a device.
func (a *App) GetDeviceSettings(device string) map[string]bool {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	out := map[string]bool{}
	for k, v := range deviceSettingDefaults {
		out[k] = v
	}
	for k, v := range loadDeviceSettings()[device] {
		out[k] = v
	}
	return out
}

// SetDeviceSetting changes one switch for a device.
func (a *App) SetDeviceSetting(device, key string, on bool) error {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	all := loadDeviceSettings()
	if all[device] == nil {
		all[device] = map[string]bool{}
	}
	all[device][key] = on
	data, err := json.MarshalIndent(all, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(deviceSettingsFile(), data, 0o644)
}

func zoomFile() string {
	dir, err := configDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "zoom")
}

// GetZoom returns the window's saved zoom (1 = 100%).
func (a *App) GetZoom() float64 {
	data, err := os.ReadFile(zoomFile())
	if err != nil {
		return 1
	}
	var z float64
	if json.Unmarshal(data, &z) != nil || z < 0.5 || z > 2 {
		return 1
	}
	return z
}

// SetZoom saves the window's zoom and applies it as real page zoom where the
// platform allows; false means the page must zoom itself (CSS zoom).
func (a *App) SetZoom(z float64) bool {
	if data, err := json.Marshal(z); err == nil {
		_ = os.WriteFile(zoomFile(), data, 0o644)
	}
	return setNativeZoom(z)
}
