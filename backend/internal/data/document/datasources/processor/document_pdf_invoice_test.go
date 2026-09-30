package processor

import (
	"bytes"
	"fmt"
	"strings"
	"testing"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/invoices"
)

func testPDFExtractsCompressedInvoiceAttachment(t *testing.T, extractor *DocumentFileExtractor) {
	var xml []byte
	text, pages, err := extractor.extractPDF(t.Context(), fixtures.PDF(fixtures.CII), "", t.TempDir(), records.DocumentProcessorOptions{}, &xml)
	if err != nil || pages != 1 || text == "" || !bytes.Equal(xml, fixtures.CII) {
		t.Fatalf("PDF invoice extraction: %d %v %s", pages, err, xml)
	}
}

func testPDFInvoiceFailureLeavesText(t *testing.T, extractor *DocumentFileExtractor) {
	var names strings.Builder
	for i := range 33 {
		fmt.Fprintf(&names, "(attachment%02d.xml) 6 0 R ", i)
	}
	for _, scenario := range []struct {
		name string
		pdf  []byte
	}{
		{"malformed recognized attachment", fixtures.PDF([]byte("<"))},
		{"oversized invoice attachment", fixtures.PDF(bytes.Repeat([]byte("x"), (2<<20)+1))},
		{"too many attachments", bytes.Replace(fixtures.PDF(fixtures.CII), []byte("[(factur-x.xml) 6 0 R]"), []byte("["+names.String()+"]"), 1)},
		{"multiple recognized attachments", bytes.Replace(fixtures.PDF(fixtures.CII), []byte("[(factur-x.xml) 6 0 R]"), []byte("[(factur-x.xml) 6 0 R (xrechnung.xml) 6 0 R]"), 1)},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var xml []byte
			var failure string
			text, pages, err := extractor.extractPDF(t.Context(), scenario.pdf, "", t.TempDir(), records.DocumentProcessorOptions{}, &xml, &failure)
			if err != nil || pages != 1 || text == "" || len(xml) != 0 || failure != "invalid_invoice" {
				t.Fatalf("optional invoice source blocked text: pages=%d failure=%q err=%v", pages, failure, err)
			}
		})
	}
}
