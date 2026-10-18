// keepawake_darwin.go keeps the Mac from going idle with caffeinate.
package main

import (
	"os"
	"os/exec"
	"strconv"
	"sync"
)

var idleInhibit struct {
	sync.Mutex
	cmd *exec.Cmd
}

// setIdleInhibit stops the display sleeping and the Mac going idle, or
// lets it again.
func setIdleInhibit(on bool) error {
	idleInhibit.Lock()
	defer idleInhibit.Unlock()
	if !on {
		if idleInhibit.cmd == nil {
			return nil
		}
		err := idleInhibit.cmd.Process.Kill()
		idleInhibit.cmd.Wait()
		idleInhibit.cmd = nil
		return err
	}
	if idleInhibit.cmd != nil {
		return nil
	}
	// -w: caffeinate ends by itself if PALT goes away.
	cmd := exec.Command("caffeinate", "-di", "-w", strconv.Itoa(os.Getpid()))
	if err := cmd.Start(); err != nil {
		return err
	}
	idleInhibit.cmd = cmd
	return nil
}
