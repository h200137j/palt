// screen_linux.go captures the screen through the PALT helper extension
// (org.palt.Screen): GNOME only lets the shell itself take screenshots and
// record without asking.
package main

import (
	"errors"

	"github.com/godbus/dbus/v5"
)

const (
	screenBusName = "org.palt.Screen"
	screenPath    = "/org/palt/Screen"
)

var errScreenHelper = errors.New("PALT's helper can't capture the screen yet: log out and back in once")

func screenSupported() bool { return true }

func screenHelper() (dbus.BusObject, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}
	var owned bool
	if conn.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, screenBusName).Store(&owned) != nil || !owned {
		return nil, errScreenHelper
	}
	return conn.Object(screenBusName, screenPath), nil
}

func takeScreenshot(path string) error {
	o, err := screenHelper()
	if err != nil {
		return err
	}
	var ok bool
	if err := o.Call(screenBusName+".Screenshot", 0, path).Store(&ok); err != nil {
		return err
	}
	if !ok {
		return errors.New("the screenshot failed")
	}
	return nil
}

// startScreencast starts recording to template plus the extension GNOME
// picks, and returns the file it records to.
func startScreencast(template string) (string, error) {
	o, err := screenHelper()
	if err != nil {
		return "", err
	}
	var ok bool
	var path string
	if err := o.Call(screenBusName+".Record", 0, template).Store(&ok, &path); err != nil {
		return "", err
	}
	if !ok {
		return "", errors.New("GNOME couldn't start recording")
	}
	return path, nil
}

func stopScreencast() error {
	o, err := screenHelper()
	if err != nil {
		return err
	}
	var ok bool
	if err := o.Call(screenBusName+".StopRecording", 0).Store(&ok); err != nil {
		return err
	}
	if !ok {
		return errors.New("GNOME couldn't stop recording")
	}
	return nil
}
