package credentials

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

func LoadFile(path string, allowCreate bool) (*EmailCredentialKeyring, error) {
	ring, err := readFile(path)
	if err == nil || !errors.Is(err, os.ErrNotExist) {
		return ring, err
	}
	if !allowCreate {
		return nil, errors.New("email credential key file is missing while encrypted credentials exist; restore the original key file or explicit keyring")
	}
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	if err := validateDirectory(directory); err != nil {
		return nil, err
	}
	file, err := os.CreateTemp(directory, ".email-key-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if err := file.Chmod(0600); err != nil {
		return nil, err
	}
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return nil, err
	}
	encoded := base64.StdEncoding.EncodeToString(key)
	clear(key)
	if _, err := io.WriteString(file, encoded+"\n"); err != nil {
		return nil, err
	}
	if err := file.Sync(); err != nil {
		return nil, err
	}
	if err := file.Close(); err != nil {
		return nil, err
	}
	if err := os.Link(file.Name(), path); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if runtime.GOOS != "windows" {
		dir, err := os.Open(directory)
		if err != nil {
			return nil, err
		}
		err = dir.Sync()
		dir.Close()
		if err != nil {
			return nil, err
		}
	}
	return readFile(path)
}

func readFile(path string) (*EmailCredentialKeyring, error) {
	if err := validateDirectory(filepath.Dir(path)); err != nil {
		return nil, err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || (runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0) {
		return nil, errors.New("email credential key file must be a private regular file (mode 0600)")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	opened, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if !os.SameFile(info, opened) {
		return nil, errors.New("email credential key file changed while opening")
	}
	body, err := io.ReadAll(io.LimitReader(file, 1025))
	if err != nil {
		return nil, err
	}
	defer clear(body)
	raw, err := json.Marshal(map[string]string{"automatic": strings.TrimSpace(string(body))})
	if err != nil {
		return nil, err
	}
	defer clear(raw)
	ring, err := NewEmailCredentialKeyring(string(raw), "automatic")
	if err != nil || len(body) > 1024 {
		return nil, errors.New("email credential key file is invalid; restore the original file")
	}
	return ring, nil
}

func validateDirectory(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.IsDir() || (runtime.GOOS != "windows" && info.Mode().Perm()&0022 != 0) {
		return errors.New("email credential key directory must be a real directory without group or public write access")
	}
	return nil
}
