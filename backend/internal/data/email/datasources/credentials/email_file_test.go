package credentials

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func TestFileConcurrentFirstStartupAndRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secrets", "email.key")
	rings := make(chan *EmailCredentialKeyring, 16)
	var group sync.WaitGroup
	for range 16 {
		group.Go(func() {
			ring, err := LoadFile(path, true)
			if err != nil {
				t.Error(err)
				return
			}
			rings <- ring
		})
	}
	group.Wait()
	close(rings)
	retained, err := LoadFile(path, false)
	if err != nil {
		t.Fatal(err)
	}
	identity := m.EmailCredentialIdentity{ProviderID: "provider", AccountID: "account", OwnerID: "owner"}
	want := m.EmailCredentials{Username: "private-user", Password: "private-password"}
	id, ciphertext, err := retained.Seal(identity, want)
	if err != nil || id != "automatic" {
		t.Fatal("automatic credentials unavailable", err)
	}
	for ring := range rings {
		if got, err := ring.Open(identity, id, ciphertext); err != nil || got != want {
			t.Fatal("concurrent startup used a different key", err)
		}
	}
	info, err := os.Stat(path)
	if err != nil || (runtime.GOOS != "windows" && info.Mode().Perm() != 0600) {
		t.Fatal("key is not private", err)
	}
	files, err := os.ReadDir(filepath.Dir(path))
	if err != nil || len(files) != 1 {
		t.Fatal("temporary keys retained", err)
	}
	other, err := LoadFile(filepath.Join(t.TempDir(), "email.key"), true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := other.Open(identity, id, ciphertext); err == nil {
		t.Fatal("different installations shared a key")
	}
}

func TestFileMissingAndInvalidKeysAreNeverReplaced(t *testing.T) {
	path := filepath.Join(t.TempDir(), "email.key")
	if _, err := LoadFile(path, false); err == nil {
		t.Fatal("missing retained key replaced")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("failed startup wrote a key", err)
	}
	for _, body := range []string{"invalid-private-key", "", strings.Repeat("a", 1025)} {
		if err := os.WriteFile(path, []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := LoadFile(path, true); err == nil || (body != "" && strings.Contains(err.Error(), body)) {
			t.Fatal("invalid key accepted or leaked", err)
		}
		if got, err := os.ReadFile(path); err != nil || !bytes.Equal(got, []byte(body)) {
			t.Fatal("invalid key overwritten", err)
		}
	}
}

func TestFileRejectsSymlinksAndPublicPermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix permissions and unprivileged symlinks are not available on Windows")
	}
	path := filepath.Join(t.TempDir(), "email.key")
	if _, err := LoadFile(path, true); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(t.TempDir(), "linked.key")
	if err := os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadFile(link, true); err == nil {
		t.Fatal("symlink key accepted")
	}
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadFile(path, true); err == nil {
		t.Fatal("public key accepted")
	}
	if err := os.Chmod(path, 0600); err != nil {
		t.Fatal(err)
	}
	directoryLink := filepath.Join(t.TempDir(), "linked-secrets")
	if err := os.Symlink(filepath.Dir(path), directoryLink); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadFile(filepath.Join(directoryLink, "email.key"), true); err == nil {
		t.Fatal("symlink directory accepted")
	}
	if err := os.Chmod(filepath.Dir(path), 0777); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadFile(path, true); err == nil {
		t.Fatal("publicly writable directory accepted")
	}
}
