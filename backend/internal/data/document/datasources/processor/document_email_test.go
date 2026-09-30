package processor

import (
	"errors"
	"strings"
	"testing"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

func TestEmailExtractionRequiresCompleteBodyButPreservesAttachmentIndependentText(t *testing.T) {
	extractor := newTestDocumentFileExtractor(t)
	options := records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto", ExtractionRevision: CurrentExtractionRevision}
	for _, raw := range []string{
		"From: sender@example.test\r\nSubject: Broken charset\r\nContent-Type: text/plain; charset=x-no-such-charset\r\n\r\nbody",
		"From: sender@example.test\r\nContent-Type: multipart/mixed; boundary=missing\r\n\r\nnot a multipart body",
	} {
		_, err := extractor.ExtractFile(t.Context(), strings.NewReader(raw), "message/rfc822", t.TempDir(), t.TempDir(), options)
		var failure records.DocumentProcessorError
		if !errors.As(err, &failure) || failure.Code != "processing_failed" {
			t.Fatalf("incomplete body was accepted: %v", err)
		}
	}
	raw := "From: sender@example.test\r\nSubject: Independent body\r\nContent-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nComplete useful body\r\n--x\r\nContent-Type: image/png\r\nContent-Disposition: attachment; filename=broken.png\r\nContent-Transfer-Encoding: base64\r\n\r\n!!!!\r\n--x--\r\n"
	result, err := extractor.ExtractFile(t.Context(), strings.NewReader(raw), "message/rfc822", t.TempDir(), t.TempDir(), options)
	if err != nil || !strings.Contains(result.Text, "Complete useful body") || result.Engine != "domabas-mime" {
		t.Fatalf("attachment failure hid complete body: %+v %v", result, err)
	}
}

func TestEmailExtractionBoundsEntireRawOriginalIncludingEpilogue(t *testing.T) {
	extractor := newTestDocumentFileExtractor(t)
	raw := "From: sender@example.test\r\nContent-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nbody\r\n--x--\r\n" + strings.Repeat("e", int(MaxFileBytes))
	_, err := extractor.ExtractFile(t.Context(), strings.NewReader(raw), "message/rfc822", t.TempDir(), t.TempDir(), records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto", ExtractionRevision: CurrentExtractionRevision})
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "resource_limit" {
		t.Fatalf("oversized epilogue bypassed raw bound: %v", err)
	}
}
