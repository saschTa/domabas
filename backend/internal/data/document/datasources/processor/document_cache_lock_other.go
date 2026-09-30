//go:build !linux && !darwin

package processor

import (
	"context"
	"errors"
	"os"
)

func lockCache(context.Context, *os.File) error {
	return errors.New("document processor requires Linux or macOS")
}
func unlockCache(*os.File) {}
