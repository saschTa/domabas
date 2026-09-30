//go:build !linux && !darwin

package filesystem

import "io/fs"

func owned(fs.FileInfo) bool { return false }
