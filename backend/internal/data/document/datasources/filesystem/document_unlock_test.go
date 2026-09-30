package filesystem

import (
	"bytes"
	"io"
	"testing"
)

func TestUnlockedCandidatePreservesOriginalAndSurvivesStagedCleanup(t *testing.T) {
	source, _, _ := setup(t)
	encrypted := []byte("%PDF-1.7 encrypted original fixture")
	original, err := source.Stage(t.Context(), reference(), "protected.pdf", bytes.NewReader(encrypted))
	if err != nil {
		t.Fatal(err)
	}
	plaintext := []byte("%PDF-1.7 unlocked fixture with different byte length")
	unlocked, err := source.StoreUnlocked(t.Context(), original, plaintext)
	if err != nil {
		t.Fatal(err)
	}
	read := func(refBytes []byte, unlockedFile bool) {
		t.Helper()
		ref := original
		if unlockedFile {
			ref = unlocked
		}
		stream, err := source.Open(t.Context(), ref)
		if err != nil {
			t.Fatal(err)
		}
		defer stream.Close()
		data, err := io.ReadAll(stream)
		if err != nil || !bytes.Equal(data, refBytes) {
			t.Fatalf("stored bytes changed: %v", err)
		}
	}
	read(encrypted, false)
	read(plaintext, true)
	if unlocked.Location != "unlocked" || unlocked.SHA256 == original.SHA256 || unlocked.Size != int64(len(plaintext)) {
		t.Fatalf("incorrect identity: %+v", unlocked)
	}
	if err = source.Remove(t.Context(), original); err != nil {
		t.Fatal(err)
	}
	read(plaintext, true)
	cleanup := original
	cleanup.Location = "final"
	if err = source.Remove(t.Context(), cleanup); err != nil {
		t.Fatal(err)
	}
	if _, err = source.Open(t.Context(), unlocked); err == nil {
		t.Fatal("unlocked candidate survived deletion")
	}
}
