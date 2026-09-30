package processor

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type fakeService struct {
	DocumentProcessorService
	embedCalls int
	err        error
}

type extractionContextService struct {
	DocumentProcessorService
	ctx context.Context
}

func (s *extractionContextService) Extract(ctx context.Context, _ io.Reader, _ string, _ models.DocumentProcessingConfiguration) (models.DocumentExtraction, error) {
	s.ctx = ctx
	return models.DocumentExtraction{}, nil
}

func TestExtractionHandlerPreservesCallerDeadline(t *testing.T) {
	for _, bounded := range []bool{false, true} {
		ctx := t.Context()
		if bounded {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, time.Hour)
			defer cancel()
		}
		service := &extractionContextService{}
		request := httptest.NewRequestWithContext(ctx, http.MethodPost, "/internal/v1/extract", bytes.NewBufferString("%PDF"))
		request.Header.Set("Content-Type", "application/pdf")
		request.Header.Set("X-Domabas-OCR-Language", "eng")
		request.Header.Set("X-Domabas-OCR-Segmentation", "auto")
		response := httptest.NewRecorder()
		NewDocumentProcessorHandler(service, nil).ServeHTTP(response, request)
		if response.Code != http.StatusOK || service.ctx == nil {
			t.Fatalf("valid extraction was rejected: %d", response.Code)
		}
		want, wantPresent := ctx.Deadline()
		actual, actualPresent := service.ctx.Deadline()
		if actualPresent != wantPresent || !actual.Equal(want) {
			t.Fatalf("handler shortened extraction deadline: %v, want %v", actual, want)
		}
	}
}

func (s *fakeService) Ready(context.Context) error { return s.err }
func (s *fakeService) Extract(context.Context, io.Reader, string, models.DocumentProcessingConfiguration) (models.DocumentExtraction, error) {
	return models.DocumentExtraction{}, s.err
}
func (s *fakeService) Embed(context.Context, models.DocumentEmbeddingSpace, string, []string) (models.DocumentEmbedding, error) {
	s.embedCalls++
	return models.DocumentEmbedding{Model: "fixed", Vectors: [][]float64{{1}}}, s.err
}
func TestPrivateProtocolRejectsUnknownOptionsAndBounds(t *testing.T) {
	service := &fakeService{}
	handler := NewDocumentProcessorHandler(service, nil)
	for _, body := range []string{`{"purpose":"query","inputs":["ok"],"model":"other"}`, `{"purpose":"query","inputs":["ok"],"url":"http://foreign"}`, `{"purpose":"other","inputs":["ok"]}`, `{"purpose":"query","inputs":[]}`, `{"purpose":"query","inputs":[" "]}`} {
		request := httptest.NewRequest(http.MethodPost, "/internal/v1/embed", bytes.NewBufferString(body))
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != 400 {
			t.Fatalf("accepted %s: %d", body, response.Code)
		}
	}
	if service.embedCalls != 0 {
		t.Fatal("invalid input reached inference")
	}
	request := httptest.NewRequest(http.MethodPost, "/internal/v1/extract", bytes.NewBufferString("%PDF"))
	request.Header.Set("Content-Type", "application/pdf")
	request.Header.Set("X-Domabas-OCR-Language", "../../outside")
	request.Header.Set("X-Domabas-OCR-Segmentation", "auto")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != 400 {
		t.Fatal("accepted arbitrary OCR language")
	}
}
func TestPrivateProtocolSanitizesFailuresAndOverload(t *testing.T) {
	for _, scenario := range []struct {
		err    error
		status int
		code   string
	}{{models.ErrOverloaded, 429, "overloaded"}, {models.ErrEmbeddingContextLength, 422, "context_length"}, {models.DocumentProcessingError{Code: "processing_timeout"}, 422, "processing_timeout"}, {models.DocumentProcessingError{Code: "internal private filename"}, 422, "processing_failed"}} {
		service := &fakeService{err: scenario.err}
		request := httptest.NewRequest(http.MethodPost, "/internal/v1/embed", bytes.NewBufferString(`{"purpose":"query","inputs":["ok"]}`))
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		NewDocumentProcessorHandler(service, nil).ServeHTTP(response, request)
		var body documentProcessorErrorResponse
		if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if response.Code != scenario.status || body.Code != scenario.code {
			t.Fatalf("unsafe failure %d %+v", response.Code, body)
		}
	}
}
