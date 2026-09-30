//go:build linux || darwin

package processor

import (
	"context"
	"errors"
	"os"
	"syscall"
	"time"
)

func lockCache(ctx context.Context, file *os.File) error {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	for {
		err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			return nil
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EAGAIN) {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}
func unlockCache(file *os.File) { _ = syscall.Flock(int(file.Fd()), syscall.LOCK_UN) }
