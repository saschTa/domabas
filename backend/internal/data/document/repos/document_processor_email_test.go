package repos_test

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	processor "github.com/domabas/domabas/backend/internal/data/document/datasources/processor"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	repos "github.com/domabas/domabas/backend/internal/data/document/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	private "github.com/domabas/domabas/backend/internal/presentation/document/handlers/processor"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/invoices"
)

type extractionProtocolSource struct {
	repos.DocumentProcessorSource
	calls     int
	directory string
	extractor *processor.DocumentFileExtractor
}

func (s *extractionProtocolSource) Extract(ctx context.Context, reader io.Reader, media string, options records.DocumentProcessorOptions) (records.DocumentExtractionResult, error) {
	s.calls++
	return s.extractor.ExtractFile(ctx, reader, media, s.directory, s.directory, options)
}
func (*extractionProtocolSource) Embed(context.Context, records.DocumentEmbeddingSpaceRecord, string, []string) (records.DocumentEmbeddingResult, error) {
	panic("unexpected embedding")
}
func (*extractionProtocolSource) Ready(context.Context) error { return nil }

func retainedNativePDF() []byte {
	stream := "BT /F1 20 Tf 25 100 Td (Retained native invoice 123) Tj ET"
	objects := []string{"<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(stream), stream)}
	var out bytes.Buffer
	out.WriteString("%PDF-1.7\n")
	offsets := []int{}
	for i, object := range objects {
		offsets = append(offsets, out.Len())
		fmt.Fprintf(&out, "%d 0 obj\n%s\nendobj\n", i+1, object)
	}
	xref := out.Len()
	fmt.Fprint(&out, "xref\n0 6\n0000000000 65535 f \n")
	for _, offset := range offsets {
		fmt.Fprintf(&out, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&out, "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", xref)
	return out.Bytes()
}

func TestPrivateProcessorRetainsV1AndReportsMIMEEvidence(t *testing.T) {
	extractor, err := processor.NewDocumentFileExtractor("")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := extractor.Close(); err != nil {
			t.Error(err)
		}
	})
	source := &extractionProtocolSource{directory: t.TempDir(), extractor: extractor}
	server := httptest.NewServer(private.NewDocumentProcessorHandler(repos.NewDocumentProcessorRepository(source), nil))
	defer server.Close()
	remote, err := processor.NewRemoteDocumentProcessorDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	repository := repos.NewDocumentProcessorRepository(remote)
	for _, revision := range []string{m.LegacyExtractionRevision, m.CurrentExtractionRevision} {
		config := m.DefaultConfiguration()
		config.ExtractionRevision = revision
		if revision == m.LegacyExtractionRevision {
			config.ManifestRevision = 1
		}
		result, err := repository.Extract(t.Context(), bytes.NewReader(retainedNativePDF()), "application/pdf", config)
		if err != nil || result.ExtractionRevision != revision || !strings.Contains(result.Text, "Retained native invoice 123") || result.Engine != "tesseract" {
			t.Fatalf("private retained/current PDF %s: %+v %v", revision, result, err)
		}
	}
	invoice, invoiceErr := repository.Extract(t.Context(), bytes.NewReader(fixtures.PDF(fixtures.CII)), "application/pdf", m.DefaultConfiguration())
	if invoiceErr != nil || !bytes.Equal(invoice.InvoiceXML, fixtures.CII) {
		t.Fatalf("private processor lost invoice XML: %v", invoiceErr)
	}
	raw := "From: sender@example.test\r\nSubject: MIME identity\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nActual email body"
	result, err := repository.Extract(t.Context(), strings.NewReader(raw), "message/rfc822", m.DefaultConfiguration())
	if err != nil || result.Engine != "domabas-mime" || result.EngineVersion != "1" || len(result.Weights) != 0 || !strings.Contains(result.Text, "Actual email body") {
		t.Fatalf("private email %+v %v", result, err)
	}
	before := source.calls
	for _, revision := range []string{"", m.LegacyExtractionRevision, "uninstalled"} {
		request, _ := http.NewRequestWithContext(t.Context(), http.MethodPost, server.URL+"/internal/v1/extract", strings.NewReader(raw))
		request.Header.Set("Content-Type", "message/rfc822")
		request.Header.Set("X-Domabas-OCR-Language", "eng")
		request.Header.Set("X-Domabas-OCR-Segmentation", "auto")
		request.Header.Set("X-Domabas-Extraction-Revision", revision)
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != http.StatusUnprocessableEntity {
			t.Fatalf("unsupported email revision %q: %d", revision, response.StatusCode)
		}
	}
	if source.calls != before {
		t.Fatal("unsupported private request reached extraction")
	}
}
