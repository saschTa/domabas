package processor

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
)

func nativePDF(width, height float64, text string) []byte {
	return nativePDFStreams(width, height, []string{fmt.Sprintf("BT /F1 20 Tf 25 100 Td (%s) Tj ET", text)})
}
func nativePDFStreams(width, height float64, streams []string) []byte {
	objects := []string{"<< /Type /Catalog /Pages 2 0 R >>", "", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"}
	var kids strings.Builder
	for _, stream := range streams {
		page := len(objects) + 1
		fmt.Fprintf(&kids, "%d 0 R ", page)
		objects = append(objects,
			fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %g %g] /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>", width, height, page+1),
			fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(stream), stream))
	}
	objects[1] = fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", kids.String(), len(streams))
	var output bytes.Buffer
	output.WriteString("%PDF-1.7\n")
	offsets := []int{}
	for i, object := range objects {
		offsets = append(offsets, output.Len())
		fmt.Fprintf(&output, "%d 0 obj\n%s\nendobj\n", i+1, object)
	}
	xref := output.Len()
	fmt.Fprintf(&output, "xref\n0 %d\n0000000000 65535 f \n", len(objects)+1)
	for _, offset := range offsets {
		fmt.Fprintf(&output, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&output, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(objects)+1, xref)
	return output.Bytes()
}
func newTestDocumentFileExtractor(t *testing.T) *DocumentFileExtractor {
	t.Helper()
	extractor, err := NewDocumentFileExtractor("")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := extractor.Close(); err != nil {
			t.Error(err)
		}
	})
	return extractor
}

func TestPDFCompilationCacheAndIsolation(t *testing.T) {
	directory := t.TempDir()
	first, err := NewDocumentFileExtractor(directory)
	if err != nil {
		t.Fatal(err)
	}
	warm, cancel := context.WithCancel(t.Context())
	err = errors.Join(first.WarmPDF(warm), first.Close())
	cancel()
	if err != nil {
		t.Fatal(err)
	}
	files := map[string]time.Time{}
	err = filepath.Walk(directory, func(path string, info os.FileInfo, err error) error {
		if err == nil && info.Mode().IsRegular() {
			files[path] = info.ModTime()
		}
		return err
	})
	if err != nil || len(files) == 0 {
		t.Fatalf("compiled PDF cache missing: %v", err)
	}
	extractor, err := NewDocumentFileExtractor(directory)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := extractor.Close(); err != nil {
			t.Error(err)
		}
	})
	t.Run("native text and limits", func(t *testing.T) { testNativePDFExtractionAndGeometryLimit(t, extractor) })
	t.Run("expanded content limits", func(t *testing.T) { testExpandedPDFLimits(t, extractor) })
	t.Run("adaptive raster", func(t *testing.T) { testPDFAdaptiveRaster(t, extractor) })
	t.Run("invoice attachment", func(t *testing.T) { testPDFExtractsCompressedInvoiceAttachment(t, extractor) })
	t.Run("invoice errors preserve text", func(t *testing.T) { testPDFInvoiceFailureLeavesText(t, extractor) })
	t.Run("cancelled extraction does not poison cache", func(t *testing.T) {
		ctx, stop := context.WithCancel(t.Context())
		stop()
		var xml []byte
		if _, _, err := extractor.extractPDF(ctx, nativePDF(300, 200, "cancelled"), "", t.TempDir(), records.DocumentProcessorOptions{}, &xml); err == nil {
			t.Fatal("cancelled PDF extraction succeeded")
		}
	})
	t.Run("concurrent documents have independent memory", func(t *testing.T) {
		var jobs sync.WaitGroup
		for _, text := range []string{"First private document", "Second private document"} {
			temp := t.TempDir()
			jobs.Go(func() {
				var xml []byte
				actual, _, err := extractor.extractPDF(t.Context(), nativePDF(300, 200, text), "", temp, records.DocumentProcessorOptions{}, &xml)
				if err != nil || strings.TrimSpace(actual) != text || len(xml) != 0 {
					t.Errorf("independent extraction: %q, %v", actual, err)
				}
			})
		}
		jobs.Wait()
	})
	for path, modified := range files {
		info, err := os.Stat(path)
		if err != nil || !info.ModTime().Equal(modified) {
			t.Errorf("compiled cache was replaced instead of reused: %s, %v", path, err)
		}
	}
}

func testNativePDFExtractionAndGeometryLimit(t *testing.T, extractor *DocumentFileExtractor) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	options := records.DocumentProcessorOptions{Language: "eng", Segmentation: "auto"}
	result, err := extractor.ExtractFile(ctx, bytes.NewReader(nativePDF(300, 200, "Independent native invoice 123")), "application/pdf", t.TempDir(), t.TempDir(), options)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(result.Text, "Independent native invoice 123") || result.Pages != 1 || len(result.Weights) != 3 {
		t.Fatalf("extraction: %+v", result)
	}
	result, err = extractor.ExtractFile(ctx, bytes.NewReader(nativePDF(50000, 50000, "Huge native page")), "application/pdf", t.TempDir(), t.TempDir(), options)
	var failure records.DocumentProcessorError
	if err != nil || !strings.Contains(result.Text, "Huge native page") {
		t.Fatalf("native text should not require a bitmap: %+v, %v", result, err)
	}
	_, err = extractor.ExtractFile(ctx, strings.NewReader("%PDF-invalid"), "application/pdf", t.TempDir(), t.TempDir(), options)
	if !errors.As(err, &failure) || failure.Code != "invalid_file" {
		t.Fatalf("invalid: %v", err)
	}
}
func TestMixedTextMergeAndOrientations(t *testing.T) {
	text := mergeText("Invoice No. 42\nStraße Berlin", "INVOICE NO 42\nSTRASSE BERLIN\nScanned total 50 EUR\nScanned total 50 EUR")
	if text != "Invoice No. 42\nStraße Berlin\nScanned total 50 EUR" {
		t.Fatalf("merge %q", text)
	}
	source := image.NewNRGBA(image.Rect(0, 0, 3, 2))
	for y := 0; y < 2; y++ {
		for x := 0; x < 3; x++ {
			source.SetNRGBA(x, y, color.NRGBA{R: uint8(y*3 + x + 1), A: 255})
		}
	}
	expected := [][]uint8{{1, 2, 3, 4, 5, 6}, {3, 2, 1, 6, 5, 4}, {6, 5, 4, 3, 2, 1}, {4, 5, 6, 1, 2, 3}, {1, 4, 2, 5, 3, 6}, {4, 1, 5, 2, 6, 3}, {6, 3, 5, 2, 4, 1}, {3, 6, 2, 5, 1, 4}}
	for orientation := 1; orientation <= 8; orientation++ {
		result := orient(source, orientation)
		index := 0
		for y := 0; y < result.Bounds().Dy(); y++ {
			for x := 0; x < result.Bounds().Dx(); x++ {
				r, _, _, _ := result.At(x, y).RGBA()
				if uint8(r>>8) != expected[orientation-1][index] {
					t.Fatalf("orientation %d index %d", orientation, index)
				}
				index++
			}
		}
	}
	if validatePixels(1, 50_000_001) == nil || validatePixels(math.MaxInt, math.MaxInt) == nil {
		t.Fatal("unsafe pixels accepted")
	}
}
func TestVerifiedCacheRejectsCorruption(t *testing.T) {
	directory := t.TempDir()
	root, err := os.OpenRoot(directory)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	data := []byte("verified model bytes")
	digest := sha256.Sum256(data)
	expected := documentProcessorArtifact{Name: "model", Size: int64(len(data)), SHA256: hex.EncodeToString(digest[:])}
	if err = os.WriteFile(directory+"/model", data, 0600); err != nil {
		t.Fatal(err)
	}
	if err = verifyArtifact(context.Background(), root, expected); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(directory+"/model", bytes.Repeat([]byte("x"), len(data)), 0600); err != nil {
		t.Fatal(err)
	}
	if err = verifyArtifact(context.Background(), root, expected); err == nil {
		t.Fatal("corrupt cache accepted")
	}
}
func TestOllamaChecksIdentityAndPrefixesWithoutTruncation(t *testing.T) {
	requests := 0
	digest := ModelDigest
	contextError := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/tags":
			json.NewEncoder(w).Encode(map[string]any{"models": []map[string]string{{"name": ModelName, "digest": digest}}})
		case "/api/embed":
			requests++
			var body documentProcessorOllamaEmbedRequest
			if json.NewDecoder(r.Body).Decode(&body) != nil {
				t.Error("invalid request")
			}
			if body.Model != ModelName || body.Truncate || len(body.Input) != 1 || body.Input[0] != "search_query: query" {
				t.Errorf("embedding request %+v", body)
			}
			if contextError {
				w.WriteHeader(400)
				json.NewEncoder(w).Encode(map[string]string{"error": "the input length exceeds the maximum context length"})
				return
			}
			vector := make([]float64, 768)
			vector[0] = 2
			json.NewEncoder(w).Encode(documentProcessorOllamaEmbedResponse{Model: ModelName, Embeddings: [][]float64{vector}})
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()
	runtime, err := NewOllamaEmbeddingDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	result, err := runtime.Embed(context.Background(), installedEmbeddingSpace(), "query", []string{"query"})
	if err != nil || result.Vectors[0][0] != 1 {
		t.Fatalf("embedding %v %v", result, err)
	}
	digest = "drift"
	if _, err = runtime.Embed(context.Background(), installedEmbeddingSpace(), "query", []string{"query"}); err == nil || requests != 1 {
		t.Fatal("drift reached inference")
	}
	digest = ModelDigest
	contextError = true
	_, err = runtime.Embed(context.Background(), installedEmbeddingSpace(), "query", []string{"query"})
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "context_length" {
		t.Fatalf("context rejection: %v", err)
	}
}
func TestEXIFOrientationParsingAndMalformedSegments(t *testing.T) {
	for orientation := 1; orientation <= 8; orientation++ {
		exif := []byte{'E', 'x', 'i', 'f', 0, 0, 'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0, byte(orientation), 0, 0, 0, 0, 0, 0, 0}
		jpeg := append([]byte{0xff, 0xd8, 0xff, 0xe1, 0, byte(len(exif) + 2)}, exif...)
		jpeg = append(jpeg, 0xff, 0xd9)
		if actual := exifOrientation(jpeg); actual != orientation {
			t.Fatalf("orientation %d parsed as %d", orientation, actual)
		}
		for length := 0; length < len(jpeg); length++ {
			_ = exifOrientation(jpeg[:length])
		}
	}
}
func TestInterruptedCacheDownloadsAreRemovedUnderBootstrapLock(t *testing.T) {
	directory := t.TempDir()
	root, err := os.OpenRoot(directory)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	stale := ".download-123e4567-e89b-12d3-a456-426614174000"
	for _, name := range []string{stale, "eng.traineddata", ".download-operator-file"} {
		if err = os.WriteFile(directory+"/"+name, []byte("preserve except owned partial"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	cache := &documentProcessorCache{weights: root}
	if err = cache.removeInterruptedDownloads(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err = root.Stat(stale); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("stale retained: %v", err)
	}
	for _, name := range []string{"eng.traineddata", ".download-operator-file"} {
		if _, err = root.Stat(name); err != nil {
			t.Fatal("removed unrelated cache file:", err)
		}
	}
}
