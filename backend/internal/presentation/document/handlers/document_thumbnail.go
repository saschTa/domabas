package handlers

import (
	"context"
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"net/http"
	"strconv"
)

func (h *DocumentHandler) GetDocumentThumbnail(ctx context.Context, request contract.GetDocumentThumbnailRequestObject) (contract.GetDocumentThumbnailResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	if h.thumbnails == nil {
		return h.failure(ctx, domain.ErrUnavailable), nil
	}
	result, err := h.thumbnails.Read(ctx, a, request.Id.String(), request.Params.Sha256)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return documentThumbnailResponse{content: result}, nil
}

type documentThumbnailResponse struct {
	content domain.DocumentThumbnailContent
}

func (r documentThumbnailResponse) VisitGetDocumentThumbnailResponse(w http.ResponseWriter) error {
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Content-Length", strconv.Itoa(len(r.content.Bytes)))
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, err := w.Write(r.content.Bytes)
	return err
}
