package models

import (
	"encoding/json"
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

type EmailErrorResponse struct {
	Status int
	Body   contract.Error
}

func NewEmailErrorResponse(status int, code, message string) EmailErrorResponse {
	return EmailErrorResponse{status, contract.Error{Code: code, Message: message}}
}
func (r EmailErrorResponse) write(w http.ResponseWriter) error {
	w.Header().Set("Content-Type", "application/json")
	if r.Status == 429 {
		w.Header().Set("Retry-After", "5")
	}
	w.WriteHeader(r.Status)
	return json.NewEncoder(w).Encode(r.Body)
}
func (r EmailErrorResponse) VisitGetEmailCapabilitiesResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitListEmailProvidersResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitCreateEmailProviderResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitGetEmailProviderResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitUpdateEmailProviderResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitDeleteEmailProviderResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitTestEmailConnectionResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitListEmailRunsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitListOwnEmailRunsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitStartEmailRunResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r EmailErrorResponse) VisitGetEmailRunResponse(w http.ResponseWriter) error { return r.write(w) }
