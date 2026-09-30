//go:build e2e

package e2e_test

import (
	"bytes"
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/processor"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/document/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/tests/fixtures"
)

func TestCompiledProcessorRetainsLegacyDocumentsAndExtractsEmail(t *testing.T) {
	base := os.Getenv("DOCUMENT_PROCESSOR_URL")
	if base == "" {
		t.Fatal("DOCUMENT_PROCESSOR_URL is required for the real private processor")
	}
	remote, err := processor.NewRemoteDocumentProcessorDataSource(base)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	if err = remote.Ready(t.Context()); err != nil {
		t.Fatal(err)
	}
	repository := repos.NewDocumentProcessorRepository(remote)
	pdf := fixtures.PDF(t, fixtures.Page{Text: "Retained invoice 731"})
	for _, revision := range []string{m.LegacyExtractionRevision, m.CurrentExtractionRevision} {
		configuration := m.DefaultConfiguration()
		configuration.ExtractionRevision = revision
		if revision == m.LegacyExtractionRevision {
			configuration.ManifestRevision = 1
		}
		result, err := repository.Extract(t.Context(), bytes.NewReader(pdf), "application/pdf", configuration)
		if err != nil || result.ExtractionRevision != revision || result.Engine != "tesseract" || !strings.Contains(result.Text, "Retained invoice 731") {
			t.Fatalf("compiled processor PDF %s: %+v %v", revision, result, err)
		}
	}
	raw := "From: sender@example.test\r\nSubject: MIME evidence\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nEmail body from the compiled processor"
	result, err := repository.Extract(t.Context(), strings.NewReader(raw), "message/rfc822", m.DefaultConfiguration())
	if err != nil || result.Engine != "domabas-mime" || result.EngineVersion != "1" || len(result.Weights) != 0 || !strings.Contains(result.Text, "Email body from the compiled processor") {
		t.Fatalf("compiled processor email: %+v %v", result, err)
	}
	for _, revision := range []string{"", m.LegacyExtractionRevision} {
		_, err = remote.Extract(t.Context(), strings.NewReader(raw), "message/rfc822", records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto", ExtractionRevision: revision})
		var failure records.DocumentProcessorError
		if !errors.As(err, &failure) || failure.Code != "configuration_unavailable" {
			t.Fatalf("compiled processor accepted email under legacy revision %q: %v", revision, err)
		}
	}
}
