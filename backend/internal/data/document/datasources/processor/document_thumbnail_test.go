package processor

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/pdf"
)

func TestMain(m *testing.M) {
	if len(os.Args) > 1 && os.Args[1] == "worker" {
		if err := RunWorker(context.Background(), os.Args[2:], os.Stdin, os.Stdout); err != nil {
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func thumbnailPNG(t *testing.T, source image.Image) []byte {
	t.Helper()
	var output bytes.Buffer
	if err := png.Encode(&output, source); err != nil {
		t.Fatal(err)
	}
	return output.Bytes()
}

func decodedThumbnail(t *testing.T, result records.DocumentThumbnailResult, err error) image.Image {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
	if result.MediaType != "image/jpeg" || len(result.Bytes) == 0 || len(result.Bytes) > models.MaxThumbnailBytes || result.Width < 1 || result.Height < 1 || result.Width > models.MaxThumbnailWidth || result.Height > models.MaxThumbnailHeight {
		t.Fatalf("invalid thumbnail metadata: %dx%d %s %d bytes", result.Width, result.Height, result.MediaType, len(result.Bytes))
	}
	decoded, err := jpeg.Decode(bytes.NewReader(result.Bytes))
	if err != nil || decoded.Bounds().Dx() != result.Width || decoded.Bounds().Dy() != result.Height {
		t.Fatalf("invalid thumbnail JPEG: %v", err)
	}
	return decoded
}

func assertThumbnailColor(t *testing.T, actual color.Color, expected color.RGBA) {
	t.Helper()
	r, g, b, _ := actual.RGBA()
	for i, values := range [][2]int{{int(r >> 8), int(expected.R)}, {int(g >> 8), int(expected.G)}, {int(b >> 8), int(expected.B)}} {
		if difference := values[0] - values[1]; difference < -8 || difference > 8 {
			t.Fatalf("channel %d: got %d, want %d", i, values[0], values[1])
		}
	}
}

func TestThumbnailPNGScalingTransparencyAndNoUpscaling(t *testing.T) {
	extractor := &DocumentFileExtractor{}
	for _, size := range []image.Point{{1600, 2400}, {40, 20}} {
		source := image.NewNRGBA(image.Rect(0, 0, size.X, size.Y))
		for y := 0; y < size.Y; y++ {
			for x := 0; x < size.X/2; x++ {
				source.SetNRGBA(x, y, color.NRGBA{R: 255, A: 128})
			}
		}
		result, err := extractor.RenderThumbnail(t.Context(), bytes.NewReader(thumbnailPNG(t, source)), "image/png")
		decoded := decodedThumbnail(t, result, err)
		width, height := 240, 360
		if size.X == 40 {
			width, height = 40, 20
		}
		if result.Width != width || result.Height != height {
			t.Fatalf("wrong PNG dimensions: %dx%d, want %dx%d", result.Width, result.Height, width, height)
		}
		assertThumbnailColor(t, decoded.At(width/4, height/2), color.RGBA{R: 255, G: 127, B: 127, A: 255})
		assertThumbnailColor(t, decoded.At(width*3/4, height/2), color.RGBA{R: 255, G: 255, B: 255, A: 255})
	}
}

func TestThumbnailJPEGAppliesAllEXIFOrientationsAfterScaling(t *testing.T) {
	source := image.NewRGBA(image.Rect(0, 0, 800, 400))
	colors := []color.RGBA{{R: 255, A: 255}, {G: 255, A: 255}, {B: 255, A: 255}, {R: 255, G: 255, A: 255}}
	for y := 0; y < 400; y++ {
		for x := 0; x < 800; x++ {
			source.SetRGBA(x, y, colors[(y/200)*2+x/400])
		}
	}
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, source, &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}
	wantCorners := [][4]int{{0, 1, 2, 3}, {1, 0, 3, 2}, {3, 2, 1, 0}, {2, 3, 0, 1}, {0, 2, 1, 3}, {2, 0, 3, 1}, {3, 1, 2, 0}, {1, 3, 0, 2}}
	extractor := &DocumentFileExtractor{}
	for orientation := 1; orientation <= 8; orientation++ {
		t.Run(strconv.Itoa(orientation), func(t *testing.T) {
			exif := []byte{'E', 'x', 'i', 'f', 0, 0, 'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0, byte(orientation), 0, 0, 0, 0, 0, 0, 0}
			data := append([]byte{0xff, 0xd8, 0xff, 0xe1, 0, byte(len(exif) + 2)}, exif...)
			data = append(data, encoded.Bytes()[2:]...)
			result, err := extractor.RenderThumbnail(t.Context(), bytes.NewReader(data), "image/jpeg")
			decoded := decodedThumbnail(t, result, err)
			width, height := 256, 128
			if orientation >= 5 {
				width, height = 180, 360
			}
			if result.Width != width || result.Height != height {
				t.Fatalf("wrong EXIF dimensions: %dx%d, want %dx%d", result.Width, result.Height, width, height)
			}
			for index, point := range []image.Point{{width / 4, height / 4}, {width * 3 / 4, height / 4}, {width / 4, height * 3 / 4}, {width * 3 / 4, height * 3 / 4}} {
				assertThumbnailColor(t, decoded.At(point.X, point.Y), colors[wantCorners[orientation-1][index]])
			}
		})
	}
}

func TestThumbnailPDFUsesFirstPageAndPreservesParsingBounds(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	extractor := newTestDocumentFileExtractor(t)
	data := nativePDFStreams(600, 900, []string{"1 0 0 rg 0 0 600 900 re f", "0 1 0 rg 0 0 600 900 re f"})
	result, err := extractor.RenderThumbnail(t.Context(), bytes.NewReader(data), "application/pdf")
	decoded := decodedThumbnail(t, result, err)
	if result.Width != 240 || result.Height != 360 {
		t.Fatalf("unexpected PDF dimensions: %dx%d", result.Width, result.Height)
	}
	assertThumbnailColor(t, decoded.At(120, 180), color.RGBA{R: 255, A: 255})
	blank, err := extractor.RenderThumbnail(t.Context(), bytes.NewReader(nativePDFStreams(100, 80, []string{""})), "application/pdf")
	decoded = decodedThumbnail(t, blank, err)
	if blank.Width != 100 || blank.Height != 80 {
		t.Fatalf("small PDF was upscaled: %dx%d", blank.Width, blank.Height)
	}
	assertThumbnailColor(t, decoded.At(50, 40), color.RGBA{R: 255, G: 255, B: 255, A: 255})
	for name, source := range map[string][]byte{
		"encrypted":                fixtures.PasswordPDF("test123", "private"),
		"too many pages":           nativePDFStreams(100, 100, make([]string, models.MaxPDFPages+1)),
		"too many objects":         nativePDFStreams(100, 100, []string{strings.Repeat("0 0 10 10 re f\n", maxPDFObjects+1)}),
		"oversized embedded image": thumbnailImageBombPDF(),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := extractor.RenderThumbnail(t.Context(), bytes.NewReader(source), "application/pdf")
			var failure records.DocumentProcessorError
			if !errors.As(err, &failure) || (failure.Code != "resource_limit" && failure.Code != "encrypted_pdf") {
				t.Fatalf("unsafe PDF accepted: %v", err)
			}
		})
	}
}

func thumbnailImageBombPDF() []byte {
	stream := "q 100 0 0 100 0 0 cm /Im0 Do Q"
	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>",
		"<< /Type /XObject /Subtype /Image /Width 50000001 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1 >>\nstream\nx\nendstream",
		fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(stream), stream),
	}
	var output bytes.Buffer
	output.WriteString("%PDF-1.7\n")
	offsets := make([]int, len(objects))
	for i, object := range objects {
		offsets[i] = output.Len()
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

type thumbnailOversizedReader struct {
	remaining int64
}

func (reader *thumbnailOversizedReader) Read(data []byte) (int, error) {
	if reader.remaining == 0 {
		return 0, io.EOF
	}
	count := min(int64(len(data)), reader.remaining)
	clear(data[:count])
	reader.remaining -= count
	return int(count), nil
}

func TestThumbnailRejectsOversizedSourceBeforeParsing(t *testing.T) {
	extractor := &DocumentFileExtractor{}
	reader := &thumbnailOversizedReader{remaining: models.MaxFileBytes + 4096}
	_, err := extractor.RenderThumbnail(t.Context(), reader, "image/png")
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) || failure.Code != "resource_limit" || reader.remaining != 4095 {
		t.Fatalf("source byte limit was not enforced before parsing: %v, remaining=%d", err, reader.remaining)
	}
}

func TestThumbnailRejectsPixelBombMalformedSourceAndCancellation(t *testing.T) {
	extractor := &DocumentFileExtractor{}
	pngData := thumbnailPNG(t, image.NewRGBA(image.Rect(0, 0, 1, 1)))
	oversized := bytes.Clone(pngData)
	binary.BigEndian.PutUint32(oversized[16:20], 50_000_001)
	binary.BigEndian.PutUint32(oversized[29:33], crc32.ChecksumIEEE(oversized[12:29]))
	for _, source := range []struct {
		data        []byte
		media, code string
	}{{oversized, "image/png", "resource_limit"}, {pngData, "image/jpeg", "invalid_file"}, {[]byte("malformed"), "image/png", "invalid_file"}, {pngData, "message/rfc822", "unsupported_media"}} {
		_, err := extractor.RenderThumbnail(t.Context(), bytes.NewReader(source.data), source.media)
		var failure records.DocumentProcessorError
		if !errors.As(err, &failure) || failure.Code != source.code {
			t.Fatalf("source validation: got %v, want %s", err, source.code)
		}
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := extractor.RenderThumbnail(ctx, bytes.NewReader(pngData), "image/png"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled thumbnail accepted: %v", err)
	}
}

func TestThumbnailWorkerSubprocessUsesBoundedCPUAdmission(t *testing.T) {
	local := newCapacityTestProcessor(t, 2)
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	local.executable = executable
	source := thumbnailPNG(t, image.NewRGBA(image.Rect(0, 0, 20, 30)))
	result, err := local.RenderThumbnail(t.Context(), bytes.NewReader(source), "image/png")
	decodedThumbnail(t, result, err)
	occupyProcessorSlots(local.extractSlot)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Millisecond)
	defer cancel()
	if _, err = local.RenderThumbnail(ctx, bytes.NewReader(source), "image/png"); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("thumbnail admission ignored cancellation: %v", err)
	}
	for range cap(local.extractSlot) {
		<-local.extractSlot
	}
	if local.requests != 0 {
		t.Fatal("thumbnail retained processor admission")
	}
}

func TestThumbnailRemoteProtocolBoundsAndValidatesResponses(t *testing.T) {
	var jpegData bytes.Buffer
	if err := jpeg.Encode(&jpegData, image.NewRGBA(image.Rect(0, 0, 25, 35)), nil); err != nil {
		t.Fatal(err)
	}
	for _, scenario := range []struct {
		name, media, data string
		status            int
		valid             bool
	}{
		{"valid", "image/jpeg", jpegData.String(), 200, true},
		{"wrong mime", "image/png", jpegData.String(), 200, false},
		{"truncated", "image/jpeg", jpegData.String()[:100], 200, false},
		{"too large", "image/jpeg", strings.Repeat("x", models.MaxThumbnailBytes+1), 200, false},
		{"transient error", "application/json", `{"code":"overloaded"}`, 429, false},
		{"unsafe error", "application/json", `{"code":"private source path"}`, 500, false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost || r.URL.Path != "/internal/v1/thumbnail" || r.Header.Get("Content-Type") != "application/pdf" {
					t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
				}
				_, _ = io.Copy(io.Discard, r.Body)
				w.Header().Set("Content-Type", scenario.media)
				w.WriteHeader(scenario.status)
				_, _ = io.WriteString(w, scenario.data)
			}))
			defer server.Close()
			remote, err := NewRemoteDocumentProcessorDataSource(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			result, err := remote.RenderThumbnail(t.Context(), strings.NewReader("source"), "application/pdf")
			if scenario.valid {
				decodedThumbnail(t, result, err)
			} else if err == nil {
				t.Fatal("invalid thumbnail response accepted")
			} else if scenario.name == "unsafe error" {
				var failure records.DocumentProcessorError
				if !errors.As(err, &failure) || failure.Code != "inference_unavailable" {
					t.Fatalf("unsafe error returned: %v", err)
				}
			}
		})
	}
}

func TestThumbnailWorkerRejectsUnsupportedMediaWithoutInference(t *testing.T) {
	var output bytes.Buffer
	if err := RunWorker(t.Context(), []string{"thumbnail", "message/rfc822"}, strings.NewReader("email"), &output); err != nil {
		t.Fatal(err)
	}
	var failure records.DocumentProcessorError
	if json.Unmarshal(output.Bytes(), &failure) != nil || failure.Code != "unsupported_media" {
		t.Fatalf("unsupported worker result: %s", output.String())
	}
}
