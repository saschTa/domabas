package processor

import records "github.com/domabas/domabas/backend/internal/data/document/models"

type documentProcessorWorkerResponse struct {
	Result *records.DocumentExtractionResult `json:"result,omitempty"`
	Error  *records.DocumentProcessorError   `json:"error,omitempty"`
}
