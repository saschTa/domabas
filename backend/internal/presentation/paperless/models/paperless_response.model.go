package models

import (
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type PaperlessErrorResponse struct {
	Status        int
	Code, Message string
}

func (r PaperlessErrorResponse) write(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}
func (r PaperlessErrorResponse) VisitGetPaperlessOptionsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r PaperlessErrorResponse) VisitStartPaperlessRunResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r PaperlessErrorResponse) VisitListPaperlessRunsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r PaperlessErrorResponse) VisitGetPaperlessRunResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r PaperlessErrorResponse) VisitCancelPaperlessRunResponse(w http.ResponseWriter) error {
	return r.write(w)
}

func (r PaperlessErrorResponse) VisitListPaperlessOutcomesResponse(w http.ResponseWriter) error {
	return r.write(w)
}

func (r PaperlessErrorResponse) VisitGetPaperlessSettingsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r PaperlessErrorResponse) VisitUpdatePaperlessSettingsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
