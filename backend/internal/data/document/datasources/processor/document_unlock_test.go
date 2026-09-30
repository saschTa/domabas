package processor

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/pdf"
)

func TestPasswordPDFUnlockPersistsReadableText(t *testing.T) {
	extractor := newTestDocumentFileExtractor(t)
	data := fixtures.PasswordPDF(" test123 ", "Unlocked searchable fixture")
	var xml []byte
	_, _, err := extractor.extractPDF(t.Context(), data, "", t.TempDir(), records.DocumentProcessorOptions{}, &xml)
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "encrypted_pdf" {
		t.Fatalf("password not detected: %v", err)
	}
	if _, err = extractor.UnlockPDF(t.Context(), bytes.NewReader(data), "test123"); !errors.As(err, &failure) || failure.Code != "invalid_pdf_password" {
		t.Fatalf("wrong password accepted: %v", err)
	}
	result, err := extractor.UnlockPDF(t.Context(), bytes.NewReader(data), " test123 ")
	if err != nil {
		t.Fatal(err)
	}
	text, pages, err := extractor.extractPDF(t.Context(), result, "", t.TempDir(), records.DocumentProcessorOptions{}, &xml)
	if err != nil || pages != 1 || !strings.Contains(text, "Unlocked searchable fixture") {
		t.Fatalf("decrypted bytes unreadable: pages=%d err=%v", pages, err)
	}
}
