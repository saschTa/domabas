package processor

import (
	"bytes"
	"context"
	"image"
	"image/jpeg"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type thumbnailRendererStub struct {
	result models.DocumentThumbnailImage
	ctx    context.Context
	calls  int
}

func (renderer *thumbnailRendererStub) RenderThumbnail(ctx context.Context, reader io.Reader, media string) (models.DocumentThumbnailImage, error) {
	renderer.ctx = ctx
	renderer.calls++
	return renderer.result, nil
}

func TestThumbnailHandlerChecksSourceAndOutputLimits(t *testing.T) {
	renderer := &thumbnailRendererStub{}
	handler := NewDocumentProcessorHandler(nil, renderer)
	for _, scenario := range []struct {
		media  string
		size   int64
		status int
	}{
		{"message/rfc822", 1, http.StatusBadRequest},
		{"image/png", models.MaxFileBytes + 1, http.StatusRequestEntityTooLarge},
	} {
		request := httptest.NewRequest(http.MethodPost, "/internal/v1/thumbnail", strings.NewReader("source"))
		request.Header.Set("Content-Type", scenario.media)
		request.ContentLength = scenario.size
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != scenario.status {
			t.Fatalf("invalid source status %d, want %d", response.Code, scenario.status)
		}
	}
	if renderer.calls != 0 {
		t.Fatal("invalid source reached renderer")
	}
	renderer.result = models.DocumentThumbnailImage{Bytes: make([]byte, models.MaxThumbnailBytes+1), Width: 1, Height: 1, MediaType: "image/jpeg"}
	request := httptest.NewRequest(http.MethodPost, "/internal/v1/thumbnail", strings.NewReader("source"))
	request.Header.Set("Content-Type", "image/png")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code == http.StatusOK {
		t.Fatal("oversized thumbnail returned")
	}
}

func TestThumbnailHandlerReturnsPrivateJPEGWithBoundedDeadline(t *testing.T) {
	var output bytes.Buffer
	if err := jpeg.Encode(&output, image.NewRGBA(image.Rect(0, 0, 10, 20)), nil); err != nil {
		t.Fatal(err)
	}
	renderer := &thumbnailRendererStub{result: models.DocumentThumbnailImage{Bytes: output.Bytes(), Width: 10, Height: 20, MediaType: "image/jpeg"}}
	request := httptest.NewRequest(http.MethodPost, "/internal/v1/thumbnail", strings.NewReader("source"))
	request.Header.Set("Content-Type", "image/png")
	response := httptest.NewRecorder()
	started := time.Now()
	NewDocumentProcessorHandler(nil, renderer).ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Header().Get("Content-Type") != "image/jpeg" || response.Header().Get("Cache-Control") != "no-store" || !bytes.Equal(response.Body.Bytes(), output.Bytes()) {
		t.Fatalf("unexpected thumbnail response: %d %v", response.Code, response.Header())
	}
	deadline, present := renderer.ctx.Deadline()
	if !present || deadline.Sub(started) > time.Minute+time.Second || deadline.Sub(started) < 59*time.Second {
		t.Fatalf("renderer deadline not bounded to one minute: %v", deadline)
	}
}
