package transport

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func ReadJSON(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	return ReadJSONLimit(w, r, 32*1024)
}

func ReadJSONLimit(w http.ResponseWriter, r *http.Request, limit int64) ([]byte, bool) {
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" {
		WriteError(w, http.StatusUnsupportedMediaType, "unsupported_media_type", "Content-Type must be application/json")
		return nil, false
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, limit))
	if err != nil {
		var maxBytes *http.MaxBytesError
		if errors.As(err, &maxBytes) {
			message := "request body exceeds its size limit"
			if limit == 32*1024 {
				message = "request body exceeds 32 KiB"
			}
			WriteError(w, http.StatusRequestEntityTooLarge, "body_too_large", message)
		} else {
			WriteError(w, http.StatusBadRequest, "invalid_request", "cannot read request body")
		}
		return nil, false
	}
	return body, true
}

func WriteError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(contract.Error{Code: code, Message: message})
}
