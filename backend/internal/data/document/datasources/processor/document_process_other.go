//go:build !linux && !darwin

package processor

import "os/exec"

func configureProcess(command *exec.Cmd) {}
