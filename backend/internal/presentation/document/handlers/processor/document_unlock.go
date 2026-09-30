package processor

import (
	"encoding/binary"
	"errors"
	"io"
	"net/http"
	"strings"
	"unicode/utf8"

	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (h *DocumentProcessorHandler) unlock(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, models.MaxFileBytes+1028)
	defer r.Body.Close()
	var prefix [4]byte
	if _, err := io.ReadFull(r.Body, prefix[:]); err != nil {
		respond(w, 400, documentProcessorErrorResponse{Code: "invalid_file"})
		return
	}
	length := binary.BigEndian.Uint32(prefix[:])
	if length < 1 || length > 1024 {
		respond(w, 400, documentProcessorErrorResponse{Code: "invalid_file"})
		return
	}
	password := make([]byte, length)
	if _, err := io.ReadFull(r.Body, password); err != nil || !utf8.Valid(password) || strings.ContainsRune(string(password), 0) {
		respond(w, 400, documentProcessorErrorResponse{Code: "invalid_file"})
		return
	}
	data, err := h.service.UnlockPDF(r.Context(), r.Body, string(password))
	clear(password)
	if errors.Is(err, models.ErrInvalidPDFPassword) {
		respond(w, 400, documentProcessorErrorResponse{Code: "invalid_pdf_password"})
		return
	}
	if err != nil {
		failure(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/pdf")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}
