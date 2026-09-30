package datasources

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
)

func TestCredentialKeyConcurrentFirstStartAndRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secrets", "paperless.key")
	keys := make(chan string, 16)
	var group sync.WaitGroup
	for range 16 {
		group.Go(func() {
			key, err := loadCredentialKey("", path, true)
			if err != nil {
				t.Error(err)
				return
			}
			keys <- key
		})
	}
	group.Wait()
	close(keys)
	retained, err := loadCredentialKey("", path, false)
	if err != nil {
		t.Fatal(err)
	}
	for key := range keys {
		if key != retained {
			t.Fatal("concurrent startup used different keys")
		}
	}
	info, err := os.Stat(path)
	if err != nil || (runtime.GOOS != "windows" && info.Mode().Perm() != 0600) {
		t.Fatal("key is not private", err)
	}
	files, err := os.ReadDir(filepath.Dir(path))
	if err != nil || len(files) != 1 {
		t.Fatal("temporary credentials were retained", files, err)
	}
	other, err := loadCredentialKey("", filepath.Join(t.TempDir(), "paperless.key"), true)
	if err != nil || other == retained {
		t.Fatal("separate installations shared generated keys", err)
	}
}

func TestCredentialKeyMissingInvalidAndLegacyConfiguration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "paperless.key")
	if _, err := loadCredentialKey("", path, false); err == nil {
		t.Fatal("missing historical key was replaced")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("failed historical startup wrote a key", err)
	}
	if err := os.WriteFile(path, []byte("invalid private key"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCredentialKey("", path, true); err == nil || strings.Contains(err.Error(), "invalid private key") {
		t.Fatal("invalid key was accepted or leaked", err)
	}
	if body, _ := os.ReadFile(path); string(body) != "invalid private key" {
		t.Fatal("invalid historical key was overwritten")
	}
	legacy := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	if key, err := loadCredentialKey(legacy, path, false); err != nil || key != legacy {
		t.Fatal("legacy configured key was not preserved", err)
	}
	for _, bad := range []string{"private-invalid-key", base64.StdEncoding.EncodeToString([]byte("short"))} {
		if _, err := loadCredentialKey(bad, path, true); err == nil || strings.Contains(err.Error(), bad) {
			t.Fatal("invalid configured key accepted or leaked", err)
		}
	}
}

func TestCredentialKeyRejectsSymlinksAndPublicFiles(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix permissions and unprivileged symlinks are not available on Windows")
	}
	path := filepath.Join(t.TempDir(), "paperless.key")
	key, err := loadCredentialKey("", path, true)
	if err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(t.TempDir(), "link.key")
	if err := os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCredentialKey("", link, true); err == nil {
		t.Fatal("symlink accepted")
	}
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCredentialKey("", path, true); err == nil || strings.Contains(err.Error(), key) {
		t.Fatal("public key file accepted or leaked", err)
	}
	if err := os.Chmod(path, 0600); err != nil {
		t.Fatal(err)
	}
	directoryLink := filepath.Join(t.TempDir(), "linked-secrets")
	if err := os.Symlink(filepath.Dir(path), directoryLink); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCredentialKey("", filepath.Join(directoryLink, "paperless.key"), true); err == nil {
		t.Fatal("symlink key directory accepted")
	}
	if err := os.Chmod(filepath.Dir(path), 0777); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCredentialKey("", path, true); err == nil {
		t.Fatal("publicly writable key directory accepted")
	}
}
