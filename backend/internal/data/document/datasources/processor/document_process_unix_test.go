//go:build linux || darwin

package processor

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestCancellationKillsWorkerDescendants(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "descendant-survived")
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	command := exec.CommandContext(ctx, "sh", "-c", `(sleep 0.4; printf survived > "$1") & wait`, "processor-test", marker)
	configureProcess(command)
	started := time.Now()
	if err := command.Run(); err == nil {
		t.Fatal("uncancelled worker")
	}
	if time.Since(started) > 2*time.Second {
		t.Fatal("worker cancellation did not wait promptly")
	}
	time.Sleep(500 * time.Millisecond)
	if _, err := os.Stat(marker); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("descendant escaped cancellation: %v", err)
	}
}
func TestCacheLockIsBoundedByContext(t *testing.T) {
	name := filepath.Join(t.TempDir(), "lock")
	first, err := os.OpenFile(name, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	second, err := os.OpenFile(name, os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	if err = lockCache(context.Background(), first); err != nil {
		t.Fatal(err)
	}
	defer unlockCache(first)
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	if err = lockCache(ctx, second); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("lock ignored context: %v", err)
	}
}
