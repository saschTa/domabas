package processor

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/klippa-app/go-pdfium/requests"
)

func testPDFAdaptiveRaster(t *testing.T, extractor *DocumentFileExtractor) {
	for _, size := range [][2]float64{{3600, 1800}, {3601, 1800}, {5952, 8418}} {
		testPDFRasterSize(t, extractor, size[0], size[1])
	}
}

func testPDFRasterSize(t *testing.T, extractor *DocumentFileExtractor, width, height float64) {
	t.Helper()
	pool, err := extractor.newPDFPool(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	instance, err := pool.GetInstanceWithContext(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer instance.Close()
	data := nativePDF(width, height, "Maximum raster size")
	document, err := instance.OpenDocument(&requests.OpenDocument{File: &data})
	if err != nil {
		t.Fatal(err)
	}
	dpi, err := pdfRenderDPI(width, height)
	if err != nil {
		t.Fatal(err)
	}
	render, err := instance.RenderPageInDPI(&requests.RenderPageInDPI{
		Page:        requests.Page{ByIndex: &requests.PageByIndex{Document: document.Document, Index: 0}},
		DPI:         dpi,
		ImageFormat: requests.RenderImageFormatGrayscale,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer render.Cleanup()
	bounds := render.Result.RenderedImage.Bounds()
	if err := validatePixels(bounds.Dx(), bounds.Dy()); err != nil {
		t.Fatalf("adaptive render exceeded pixel budget: size=%gx%g dpi=%d bounds=%v", width, height, dpi, bounds)
	}
	if width == 3600 && height == 1800 && (bounds.Dx() != 10000 || bounds.Dy() != 5000) {
		t.Fatalf("exact-limit render changed: %v", bounds)
	}
}

func TestPDFRenderDPI(t *testing.T) {
	for _, tc := range []struct {
		width, height float64
		dpi           int
	}{
		{595.2, 841.8, 200},
		{3600, 1800, 200},
		{3600.001, 1800, 199},
		{5952, 8418, 71},
		{8418, 5952, 71},
		{50000, 50000, 10},
	} {
		dpi, err := pdfRenderDPI(tc.width, tc.height)
		if err != nil || dpi != tc.dpi {
			t.Fatalf("size=%gx%g: dpi=%d, want=%d, err=%v", tc.width, tc.height, dpi, tc.dpi, err)
		}
	}
	for _, size := range [][2]float64{{0, 72}, {72, 0}, {-1, 72}, {72, -1}, {math.NaN(), 72}, {72, math.NaN()}, {math.Inf(1), 72}, {72, math.Inf(-1)}, {math.MaxFloat64, 72}, {1e12, 1e12}} {
		_, err := pdfRenderDPI(size[0], size[1])
		var failure records.DocumentProcessorError
		if !errors.As(err, &failure) || failure.Code != "resource_limit" {
			t.Fatalf("unsafe geometry accepted: %v, err=%v", size, err)
		}
	}
}

func testExpandedPDFLimits(t *testing.T, extractor *DocumentFileExtractor) {
	const stream = "BT /F1 20 Tf 25 100 Td (Invoice 123) Tj ET\n"
	for _, tc := range []struct {
		name           string
		pages, objects int
		width, height  float64
		fails          bool
	}{
		{"200 pages", 200, 1, 300, 200, false},
		{"201 pages", 201, 1, 300, 200, true},
		{"20000 objects across pages", 2, 10000, 300, 200, false},
		{"20002 objects across pages", 2, 10001, 300, 200, false},
		{"ordinary dense six-page document", 6, 7500, 300, 200, false},
		{"20001 objects on one page", 1, 20001, 300, 200, true},
		{"30 megapixel page", 1, 1, 2160, 1800, false},
		{"above previous pixel limit", 1, 1, 2161, 1800, false},
		{"50 megapixel page", 1, 1, 3600, 1800, false},
		{"oversized native page", 1, 1, 3601, 1800, false},
		{"native page beyond minimum raster DPI", 1, 1, 1e12, 1e12, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			streams := make([]string, tc.pages)
			for i := range streams {
				streams[i] = strings.Repeat(stream, tc.objects)
			}
			var xml []byte
			text, pages, err := extractor.extractPDF(t.Context(), nativePDFStreams(tc.width, tc.height, streams), "", t.TempDir(), records.DocumentProcessorOptions{}, &xml)
			if tc.fails {
				var failure records.DocumentProcessorError
				if !errors.As(err, &failure) || failure.Code != "resource_limit" {
					t.Fatalf("expected resource_limit, got %v", err)
				}
			} else if err != nil || pages != tc.pages || !strings.Contains(text, "Invoice 123") {
				t.Fatalf("supported PDF failed: pages=%d err=%v", pages, err)
			}
		})
	}
}

func TestImagePixelBoundary(t *testing.T) {
	for _, dimensions := range [][2]int{{6000, 5000}, {6001, 5000}, {10000, 5000}, {5000, 10000}, {50_000_000, 1}, {1, 50_000_000}} {
		if err := validatePixels(dimensions[0], dimensions[1]); err != nil {
			t.Fatalf("supported dimensions %v rejected: %v", dimensions, err)
		}
	}
	for _, dimensions := range [][2]int{{10001, 5000}, {5000, 10001}, {50_000_001, 1}, {1, 50_000_001}, {0, 100}, {-1, 100}} {
		if err := validatePixels(dimensions[0], dimensions[1]); err == nil {
			t.Fatalf("invalid dimensions accepted: %v", dimensions)
		}
	}
}

func TestProcessorResponseFitsMaximumEscapedTextAndInvoice(t *testing.T) {
	expected := records.DocumentExtractionResult{Text: strings.Repeat("<", 2<<20), InvoiceXML: bytes.Repeat([]byte("x"), 2<<20), Pages: 200}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewEncoder(w).Encode(expected); err != nil {
			t.Error(err)
		}
	}))
	defer server.Close()
	remote, err := NewRemoteDocumentProcessorDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	result, err := remote.Extract(t.Context(), strings.NewReader("%PDF"), "application/pdf", records.DocumentProcessorOptions{})
	if err != nil || result.Text != expected.Text || !bytes.Equal(result.InvoiceXML, expected.InvoiceXML) {
		t.Fatalf("maximum response did not survive transport: %v", err)
	}
	var output documentProcessorBoundedBuffer
	output.limit = MaxRPCBytes
	if err := json.NewEncoder(&output).Encode(documentProcessorWorkerResponse{Result: &expected}); err != nil || output.exceeded {
		t.Fatalf("maximum response exceeded worker output: %v", err)
	}
}
