package processor

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentProcessorService interface {
	UnlockPDF(context.Context, io.Reader, string) ([]byte, error)
	Extract(context.Context, io.Reader, string, models.DocumentProcessingConfiguration) (models.DocumentExtraction, error)
	Embed(context.Context, models.DocumentEmbeddingSpace, string, []string) (models.DocumentEmbedding, error)
	Ready(context.Context) error
}
type DocumentThumbnailRenderer interface {
	RenderThumbnail(context.Context, io.Reader, string) (models.DocumentThumbnailImage, error)
}
type DocumentProcessorHandler struct {
	service    DocumentProcessorService
	thumbnails DocumentThumbnailRenderer
}

func NewDocumentProcessorHandler(service DocumentProcessorService, thumbnails DocumentThumbnailRenderer) http.Handler {
	handler := &DocumentProcessorHandler{service: service, thumbnails: thumbnails}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /readyz", handler.ready)
	mux.HandleFunc("POST /internal/v1/extract", handler.extract)
	mux.HandleFunc("POST /internal/v1/unlock", handler.unlock)
	mux.HandleFunc("POST /internal/v1/embed", handler.embed)
	mux.HandleFunc("POST /internal/v1/thumbnail", handler.thumbnail)
	return mux
}
func respond(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if value != nil {
		_ = json.NewEncoder(w).Encode(value)
	}
}
func failure(w http.ResponseWriter, err error) {
	code := "processing_failed"
	status := http.StatusUnprocessableEntity
	var processing models.DocumentProcessingError
	switch {
	case errors.Is(err, models.ErrOverloaded):
		code = "overloaded"
		status = http.StatusTooManyRequests
	case errors.Is(err, models.ErrEmbeddingContextLength):
		code = "context_length"
	case errors.Is(err, models.ErrTooLarge):
		code = "resource_limit"
		status = http.StatusRequestEntityTooLarge
	case errors.Is(err, models.ErrUnavailable):
		code = "inference_unavailable"
		status = http.StatusServiceUnavailable
	case errors.As(err, &processing):
		if models.ValidFailureCode(processing.Code) {
			code = processing.Code
		}
		if processing.Retryable {
			status = http.StatusServiceUnavailable
		}
	case errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded):
		code = "processing_timeout"
	}
	respond(w, status, documentProcessorErrorResponse{Code: code})
}
func (h *DocumentProcessorHandler) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if err := h.service.Ready(ctx); err != nil {
		failure(w, err)
		return
	}
	respond(w, http.StatusOK, nil)
}
func (h *DocumentProcessorHandler) extract(w http.ResponseWriter, r *http.Request) {
	configuration := models.DefaultConfiguration()
	configuration.ExtractionRevision = r.Header.Get("X-Domabas-Extraction-Revision")
	if configuration.ExtractionRevision == "" || configuration.ExtractionRevision == models.LegacyExtractionRevision {
		configuration.ManifestRevision = 1
	}
	configuration.Language = r.Header.Get("X-Domabas-OCR-Language")
	configuration.Segmentation = r.Header.Get("X-Domabas-OCR-Segmentation")
	if configuration.Validate() != nil {
		respond(w, http.StatusBadRequest, documentProcessorErrorResponse{Code: "invalid_file"})
		return
	}
	mediaType := r.Header.Get("Content-Type")
	if mediaType != "application/pdf" && mediaType != "image/png" && mediaType != "image/jpeg" && mediaType != "message/rfc822" {
		respond(w, http.StatusBadRequest, documentProcessorErrorResponse{Code: "invalid_file"})
		return
	}
	configuration = configuration.WithLegacyIdentity()
	if _, err := configuration.ExtractionIdentity(mediaType); err != nil {
		failure(w, err)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, models.MaxFileBytes+1)
	defer r.Body.Close()
	result, err := h.service.Extract(r.Context(), r.Body, mediaType, configuration)
	if err != nil {
		failure(w, err)
		return
	}
	weights := make([]documentProcessorWeightResponse, len(result.Weights))
	for i, weight := range result.Weights {
		weights[i] = documentProcessorWeightResponse{Name: weight.Name, SHA256: weight.SHA256}
	}
	respond(w, http.StatusOK, documentProcessorExtractionResponse{InvoiceXML: result.InvoiceXML, ExtractionRevision: result.ExtractionRevision, Text: result.Text, Pages: result.Pages, Engine: result.Engine, EngineVersion: result.EngineVersion, Weights: weights})
}
func (h *DocumentProcessorHandler) embed(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Content-Type") != "application/json" {
		respond(w, http.StatusBadRequest, documentProcessorErrorResponse{Code: "invalid_file"})
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 128<<10)
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var body documentProcessorEmbedRequest
	if decoder.Decode(&body) != nil || decoder.Decode(&struct{}{}) != io.EOF || (body.Purpose != "document" && body.Purpose != "query") || len(body.Inputs) < 1 || len(body.Inputs) > 8 {
		respond(w, http.StatusBadRequest, documentProcessorErrorResponse{Code: "resource_limit"})
		return
	}
	for _, input := range body.Inputs {
		if len(input) > 8192 || strings.TrimSpace(input) == "" {
			respond(w, http.StatusBadRequest, documentProcessorErrorResponse{Code: "resource_limit"})
			return
		}
	}
	result, err := h.service.Embed(r.Context(), models.DocumentEmbeddingSpace(body.Space), body.Purpose, body.Inputs)
	if err != nil {
		failure(w, err)
		return
	}
	respond(w, http.StatusOK, documentProcessorEmbeddingResponse{Space: documentProcessorEmbeddingSpace(result.Space), Model: result.Model, Digest: result.Digest, Vectors: result.Vectors})
}
