package filesystem

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/google/uuid"
)

func setup(t *testing.T) (*DocumentFileSystemDataSource, string, string) {
	t.Helper()
	base := t.TempDir()
	staged, final := filepath.Join(base, "staged"), filepath.Join(base, "final")
	source, err := NewDocumentFileSystemDataSource(staged, final)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = source.Close() })
	return source, staged, final
}
func reference() records.DocumentContentReference {
	return records.DocumentContentReference{AccountID: uuid.NewString(), UploaderID: uuid.NewString(), DocumentID: uuid.NewString(), Location: "staged"}
}
func payload() []byte {
	return append([]byte{137, 80, 78, 71, 13, 10, 26, 10}, bytes.Repeat([]byte("original byte content"), 30)...)
}
func TestStagePromotionRetainsReadableCopies(t *testing.T) {
	source, staged, final := setup(t)
	ctx := context.Background()
	data := payload()
	ref, err := source.Stage(ctx, reference(), "../unsafe\r\nname.png", bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(data)
	if ref.MediaType != "image/png" || ref.SHA256 != hex.EncodeToString(digest[:]) || strings.ContainsAny(ref.OriginalFilename, "/\r\n") || ref.Size != int64(len(data)) {
		t.Fatalf("invalid identity: %+v", ref)
	}
	name, _ := relative(ref)
	info, err := os.Stat(filepath.Join(staged, name))
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("file not private: %v %v", info, err)
	}
	finalRef, err := source.Promote(ctx, ref)
	if err != nil {
		t.Fatal(err)
	}
	if finalRef.Location != "final" {
		t.Fatal("not finalized")
	}
	if _, err = source.Promote(ctx, ref); err != nil {
		t.Fatal("idempotent promotion:", err)
	}
	orphan := filepath.Join(final, name+"."+uuid.NewString()+".tmp")
	if err = os.WriteFile(orphan, []byte("partial"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = source.Remove(ctx, ref); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(orphan); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("orphan survived: %v", err)
	}
	for _, authorized := range []records.DocumentContentReference{ref, finalRef} {
		stream, err := source.Open(ctx, authorized)
		if err != nil {
			t.Fatal(err)
		}
		actual, err := io.ReadAll(stream)
		stream.Close()
		if err != nil || !bytes.Equal(actual, data) {
			t.Fatal("original unreadable")
		}
	}
	if err = source.Remove(ctx, ref); err != nil {
		t.Fatal("idempotent cleanup:", err)
	}
	if err = source.Ready(ctx); err != nil {
		t.Fatal(err)
	}
}
func TestStorageRejectsEscapesCorruptionAndOverlappingRoots(t *testing.T) {
	source, staged, final := setup(t)
	ctx := context.Background()
	ref := reference()
	bad := ref
	bad.AccountID = "../outside"
	if _, err := source.Stage(ctx, bad, "input", bytes.NewReader(payload())); err == nil {
		t.Fatal("accepted path")
	}
	if _, err := NewDocumentFileSystemDataSource(staged, filepath.Join(staged, "nested")); err == nil {
		t.Fatal("accepted overlapping roots")
	}
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(staged, ref.AccountID)); err != nil {
		t.Fatal(err)
	}
	if _, err := source.Stage(ctx, ref, "input", bytes.NewReader(payload())); err == nil {
		t.Fatal("followed symlink")
	}
	ref, err := source.Stage(ctx, reference(), "input.png", bytes.NewReader(payload()))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = source.Promote(ctx, ref); err != nil {
		t.Fatal(err)
	}
	name, _ := relative(ref)
	if err = os.WriteFile(filepath.Join(final, name), bytes.Repeat([]byte("x"), int(ref.Size)), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = source.Promote(ctx, ref); err == nil {
		t.Fatal("reused corrupt final")
	}
	if err = source.Remove(ctx, ref); err != nil {
		t.Fatal(err)
	}
	if _, err = source.Open(ctx, ref); err == nil {
		t.Fatal("fallback accepted corrupt final")
	}
}
func TestUploadBoundsAndNamespaceIsolation(t *testing.T) {
	source, _, _ := setup(t)
	ctx := context.Background()
	data := payload()
	first, err := source.Stage(ctx, reference(), "a.png", bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	second := first
	second.AccountID = uuid.NewString()
	second, err = source.Stage(ctx, second, "a.png", bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	if err = source.Remove(ctx, first); err != nil {
		t.Fatal(err)
	}
	stream, err := source.Open(ctx, second)
	if err != nil {
		t.Fatal(err)
	}
	stream.Close()
	_, err = source.Stage(ctx, reference(), "wrong.png", strings.NewReader("not an image"))
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "unsupported_media" {
		t.Fatalf("signature: %v", err)
	}
	exact := io.MultiReader(bytes.NewReader(data[:8]), io.LimitReader(zeroReader{}, (100<<20)-8))
	accepted, err := source.Stage(ctx, reference(), "maximum.png", exact)
	if err != nil || accepted.Size != 100<<20 {
		t.Fatalf("100 MiB original: size=%d err=%v", accepted.Size, err)
	}
	stream, err = source.Open(ctx, accepted)
	if err != nil {
		t.Fatal(err)
	}
	copied, err := io.Copy(io.Discard, stream)
	stream.Close()
	if err != nil || copied != 100<<20 {
		t.Fatalf("100 MiB read: size=%d err=%v", copied, err)
	}
	large := io.MultiReader(bytes.NewReader(data[:8]), io.LimitReader(zeroReader{}, (100<<20)-7))
	_, err = source.Stage(ctx, reference(), "large.png", large)
	if !errors.As(err, &failure) || failure.Code != "too_large" {
		t.Fatalf("bound: %v", err)
	}
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err = source.Stage(cancelled, reference(), "cancel.png", bytes.NewReader(data)); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancellation: %v", err)
	}
}

type zeroReader struct{}

func (zeroReader) Read(data []byte) (int, error) { clear(data); return len(data), nil }
