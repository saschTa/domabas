package processor

import (
	"context"
	"net/http"
	"strconv"
	"time"

	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (h *DocumentProcessorHandler) thumbnail(w http.ResponseWriter, r *http.Request) {
	mediaType := r.Header.Get("Content-Type")
	if mediaType != "application/pdf" && mediaType != "image/png" && mediaType != "image/jpeg" {
		respond(w, http.StatusBadRequest, documentProcessorErrorResponse{Code: "unsupported_media"})
		return
	}
	if r.ContentLength > models.MaxFileBytes {
		failure(w, models.ErrTooLarge)
		return
	}
	if h.thumbnails == nil {
		failure(w, models.ErrUnavailable)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), time.Minute)
	defer cancel()
	r.Body = http.MaxBytesReader(w, r.Body, models.MaxFileBytes+1)
	defer r.Body.Close()
	result, err := h.thumbnails.RenderThumbnail(ctx, r.Body, mediaType)
	if err != nil {
		failure(w, err)
		return
	}
	if result.MediaType != "image/jpeg" || len(result.Bytes) == 0 || len(result.Bytes) > models.MaxThumbnailBytes || result.Width < 1 || result.Height < 1 || result.Width > models.MaxThumbnailWidth || result.Height > models.MaxThumbnailHeight {
		failure(w, models.DocumentProcessingError{Code: "processing_failed"})
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Content-Length", strconv.Itoa(len(result.Bytes)))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	_, _ = w.Write(result.Bytes)
}
