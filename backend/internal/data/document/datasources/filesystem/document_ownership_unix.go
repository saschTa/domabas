//go:build linux || darwin

package filesystem

import (
	"io/fs"
	"os"
	"syscall"
)

func owned(info fs.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && int(stat.Uid) == os.Getuid()
}
