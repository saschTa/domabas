package filesystem

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

func TestReadinessLeavesStorageUnchanged(t *testing.T) {
	source, staged, final := setup(t)
	roots := []string{staged, final}
	modified := time.Date(2001, time.January, 1, 0, 0, 0, 0, time.UTC)
	for _, root := range roots {
		if err := os.WriteFile(filepath.Join(root, "retained"), []byte("original content"), 0600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(root, modified, modified); err != nil {
			t.Fatal(err)
		}
	}
	for range 3 {
		if err := source.Ready(t.Context()); err != nil {
			t.Fatal(err)
		}
	}
	for _, root := range roots {
		info, err := os.Stat(root)
		if err != nil {
			t.Fatal(err)
		}
		if !info.ModTime().Equal(modified) {
			t.Fatalf("readiness modified directory %s: %v", root, info.ModTime())
		}
		entries, err := os.ReadDir(root)
		if err != nil {
			t.Fatal(err)
		}
		if len(entries) != 1 || entries[0].Name() != "retained" {
			t.Fatalf("readiness changed directory contents: %v", entries)
		}
		content, err := os.ReadFile(filepath.Join(root, "retained"))
		if err != nil || string(content) != "original content" {
			t.Fatalf("readiness changed retained content: %q, %v", content, err)
		}
	}
}

func TestReadinessRejectsCanceledContext(t *testing.T) {
	source, _, _ := setup(t)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if err := source.Ready(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("readiness returned %v, want canceled context", err)
	}
}

func TestReadinessRejectsEitherUnavailableStorageRoot(t *testing.T) {
	for _, root := range []string{"ingestion", "final"} {
		t.Run(root, func(t *testing.T) {
			source, _, _ := setup(t)
			closed := source.ingestion
			if root == "final" {
				closed = source.final
			}
			if err := closed.Close(); err != nil {
				t.Fatal(err)
			}
			var unavailable records.DocumentProcessorError
			if err := source.Ready(t.Context()); !errors.As(err, &unavailable) || unavailable.Code != "storage_unavailable" {
				t.Fatalf("readiness returned %v, want storage_unavailable", err)
			}
		})
	}
}
