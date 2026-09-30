package mimecontent

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
)

func TestIndependentMalformedAttachmentConsumerPreservesReadableSiblings(t *testing.T) {
	input := "Content-Type: multipart/mixed; boundary=x\r\n\r\n" +
		"--x\r\nContent-Type: text/plain\r\n\r\nreadable body\r\n" +
		"--x\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=bad.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\n%%%%\r\n" +
		"--x\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=good.pdf\r\n\r\n%PDF-good\r\n--x--\r\n"
	var parts []r.DocumentEmailPart
	var good string
	result, err := Inspect(context.Background(), strings.NewReader(input), func(part r.DocumentEmailPart) error {
		parts = append(parts, part)
		if part.Reader == nil {
			return nil
		}
		body, err := io.ReadAll(part.Reader)
		if part.Path == "3" {
			good = string(body)
		}
		return err
	})
	if err != nil || result.TextFailures || result.Text != "readable body" || !result.ContentFailures || good != "%PDF-good" {
		t.Fatalf("malformed attachment consumption lost valid siblings: text=%q textFailed=%v contentFailed=%v good=%q parts=%+v err=%v", result.Text, result.TextFailures, result.ContentFailures, good, parts, err)
	}
}

func TestIndependentNestedHeaderAcceptanceLimitPreservesOtherParts(t *testing.T) {
	for _, headers := range []string{
		"X-Large: " + strings.Repeat("x", (64<<10)+1) + "\r\n",
		strings.Repeat("X-Tiny: a\r\n", 201),
	} {
		input := "Content-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\n" + headers + "\r\nignored\r\n--x\r\nContent-Type: text/plain\r\n\r\nsafe sibling\r\n--x--\r\n"
		if err := Validate(strings.NewReader(input)); err != nil {
			t.Fatalf("downstream invalid part rejected raw envelope: %v", err)
		}
		result, err := Inspect(context.Background(), strings.NewReader(input), nil)
		if err != nil || !result.ContentFailures || !strings.Contains(result.Text, "safe sibling") {
			t.Fatalf("nested header limit lost safely bounded sibling: %+v %v", result, err)
		}
	}
}

func TestIndependentNestedMessageIsSkippedWithoutRecursing(t *testing.T) {
	input := "Content-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nouter body\r\n--x\r\nContent-Type: message/rfc822\r\n\r\nSubject: hidden\r\nContent-Type: multipart/mixed; boundary=inside\r\n\r\n--inside\r\nContent-Type: application/pdf\r\n\r\n%PDF-hidden\r\n--inside--\r\n--x--\r\n"
	var parts []r.DocumentEmailPart
	result, err := Inspect(context.Background(), strings.NewReader(input), func(part r.DocumentEmailPart) error {
		parts = append(parts, part)
		return nil
	})
	if err != nil || len(parts) != 1 || parts[0].Path != "2" || parts[0].Status != "skipped" || parts[0].FailureCode != "unsupported_media" || result.Text != "outer body" {
		t.Fatalf("nested message was imported or text leaked: %+v %+v %v", result, parts, err)
	}
}

func TestIndependentTransferDecodeErrorDoesNotMaskStorageFailure(t *testing.T) {
	storageErr := errors.New("test storage unavailable")
	input := "Subject: kept original\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=file.pdf\r\n\r\n%PDF-valid"
	_, err := Inspect(context.Background(), strings.NewReader(input), func(part r.DocumentEmailPart) error { return storageErr })
	if !errors.Is(err, storageErr) {
		t.Fatalf("external storage failure was misclassified as a permanent part error: %v", err)
	}
}

func TestIndependentRawEnvelopeRejectsHeaderlessAndNULTaintedInputs(t *testing.T) {
	for _, value := range []string{
		"X-Only: not-mail\r\n\r\nbody",
		"Subject: missing separator\r\nbody",
		"Subject: null\x00value\r\n\r\nbody",
		"Subject: " + strings.Repeat("x", 64<<10) + "\r\n\r\nbody",
	} {
		if err := Validate(strings.NewReader(value)); !errors.Is(err, ErrEnvelope) {
			t.Fatalf("invalid outer framing accepted: bytes=%d err=%v", len(value), err)
		}
	}
}
