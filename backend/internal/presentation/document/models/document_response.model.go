package models

import (
	"encoding/json"
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

type DocumentErrorResponse struct {
	Status int
	Body   contract.Error
}

func NewDocumentErrorResponse(status int, code, message string) DocumentErrorResponse {
	return DocumentErrorResponse{Status: status, Body: contract.Error{Code: code, Message: message}}
}
func (response DocumentErrorResponse) write(w http.ResponseWriter) error {
	w.Header().Set("Content-Type", "application/json")
	if response.Status == http.StatusTooManyRequests {
		w.Header().Set("Retry-After", "1")
	}
	w.WriteHeader(response.Status)
	return json.NewEncoder(w).Encode(response.Body)
}
func (response DocumentErrorResponse) VisitUploadDocumentResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitGetDocumentEmailLinksResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitGetDocumentEmailParentsResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitUpdateDocumentResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitDownloadDocumentResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitGetDocumentProcessingResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitRetryDocumentResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitSearchDocumentsResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitListDocumentVocabularyResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitGetDocumentProcessingConfigurationResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitGetDocumentModelContextResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitUpdateDocumentProcessingConfigurationResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitGetDocumentOCRResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitUpdateDocumentOCRResponse(w http.ResponseWriter) error {
	return response.write(w)
}
func (response DocumentErrorResponse) VisitDeleteDocumentResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitGetNamespaceDocumentProcessingResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitListDocumentJobsResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitGetDocumentJobResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitListDocumentReindexBatchesResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitCreateDocumentReindexBatchResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitGetDocumentReindexBatchResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitListSystemDocumentReindexBatchesResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitCreateSystemDocumentReindexBatchResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitGetSystemDocumentReindexBatchResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitRetryDocumentAIResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitUnlockDocumentResponse(w http.ResponseWriter) error {
	return response.write(w)
}

func (response DocumentErrorResponse) VisitGetDocumentThumbnailResponse(w http.ResponseWriter) error {
	return response.write(w)
}
