package routes

import (
	"bytes"
	"errors"
	"io"
	"net/http"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/oapi-codegen/runtime/types"
)

func (server *validatedDocumentServer) UpdateDocumentOCR(w http.ResponseWriter, r *http.Request, id types.UUID) {
	body, ok := transport.ReadJSONLimit(w, r, 6*domain.MaxOCRBytes+4096)
	if !ok {
		return
	}
	if _, err := models.DecodeOCR(body); err != nil {
		if errors.Is(err, domain.ErrTooLarge) {
			transport.WriteError(w, 413, "body_too_large", "OCR correction exceeds a limit")
		} else {
			transport.WriteError(w, 400, "invalid_request", err.Error())
		}
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	server.ServerInterface.UpdateDocumentOCR(w, r, id)
}
