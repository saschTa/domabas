package repos_test

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"net/http/httptest"
	"testing"

	processor "github.com/domabas/domabas/backend/internal/data/document/datasources/processor"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	repos "github.com/domabas/domabas/backend/internal/data/document/repos"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
	private "github.com/domabas/domabas/backend/internal/presentation/document/handlers/processor"
)

type thumbnailProcessorSourceStub struct {
	result records.DocumentThumbnailResult
	err    error
}

func (source *thumbnailProcessorSourceStub) RenderThumbnail(context.Context, io.Reader, string) (records.DocumentThumbnailResult, error) {
	return source.result, source.err
}

func TestThumbnailProcessorRepositoryRejectsInvalidArtifact(t *testing.T) {
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, image.NewRGBA(image.Rect(0, 0, 30, 40)), nil); err != nil {
		t.Fatal(err)
	}
	valid := records.DocumentThumbnailResult{Bytes: encoded.Bytes(), Width: 30, Height: 40, MediaType: "image/jpeg"}
	for _, change := range []func(*records.DocumentThumbnailResult){
		func(result *records.DocumentThumbnailResult) { result.Width = 31 },
		func(result *records.DocumentThumbnailResult) { result.Height = models.MaxThumbnailHeight + 1 },
		func(result *records.DocumentThumbnailResult) { result.MediaType = "image/png" },
		func(result *records.DocumentThumbnailResult) { result.Bytes = result.Bytes[:100] },
		func(result *records.DocumentThumbnailResult) { result.Bytes = make([]byte, models.MaxThumbnailBytes+1) },
	} {
		result := valid
		change(&result)
		repository := repos.NewDocumentThumbnailProcessorRepository(&thumbnailProcessorSourceStub{result: result})
		_, err := repository.RenderThumbnail(t.Context(), bytes.NewReader(nil), "image/png")
		var failure models.DocumentProcessingError
		if !errors.As(err, &failure) || !failure.Retryable || failure.Code != "processing_failed" {
			t.Fatalf("invalid processor artifact accepted or suppressed permanently: %v", err)
		}
	}
}

func TestThumbnailProcessorRepositoryKeepsTransientFailuresRetryable(t *testing.T) {
	for _, code := range []string{"processing_failed", "processing_timeout", "inference_unavailable", "invalid_file", "encrypted_pdf", "resource_limit"} {
		repository := repos.NewDocumentThumbnailProcessorRepository(&thumbnailProcessorSourceStub{err: records.DocumentProcessorError{Code: code}})
		_, err := repository.RenderThumbnail(t.Context(), bytes.NewReader(nil), "application/pdf")
		var failure models.DocumentProcessingError
		if !errors.As(err, &failure) || failure.Code != code {
			t.Fatalf("lost processor failure %s: %v", code, err)
		}
		wantRetry := code == "processing_failed" || code == "processing_timeout" || code == "inference_unavailable"
		if failure.Retryable != wantRetry {
			t.Fatalf("processor failure %s retryability is %v, want %v", code, failure.Retryable, wantRetry)
		}
	}
}

func TestThumbnailProcessorPrivateProtocolRoundTrip(t *testing.T) {
	extractor, err := processor.NewDocumentFileExtractor("")
	if err != nil {
		t.Fatal(err)
	}
	defer extractor.Close()
	server := httptest.NewServer(private.NewDocumentProcessorHandler(nil, repos.NewDocumentThumbnailProcessorRepository(extractor)))
	defer server.Close()
	remote, err := processor.NewRemoteDocumentProcessorDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	var source bytes.Buffer
	if err = png.Encode(&source, image.NewNRGBA(image.Rect(0, 0, 600, 1000))); err != nil {
		t.Fatal(err)
	}
	result, err := repos.NewDocumentThumbnailProcessorRepository(remote).RenderThumbnail(t.Context(), &source, "image/png")
	if err != nil {
		t.Fatal(err)
	}
	if result.MediaType != "image/jpeg" || result.Width != 216 || result.Height != 360 || len(result.Bytes) > models.MaxThumbnailBytes {
		t.Fatalf("thumbnail protocol lost bounded metadata: %dx%d %s %d", result.Width, result.Height, result.MediaType, len(result.Bytes))
	}
	decoded, err := jpeg.Decode(bytes.NewReader(result.Bytes))
	if err != nil {
		t.Fatal(err)
	}
	r, g, b, _ := decoded.At(100, 100).RGBA()
	if r != 65535 || g != 65535 || b != 65535 {
		t.Fatal("transparent thumbnail background was not white")
	}
}
