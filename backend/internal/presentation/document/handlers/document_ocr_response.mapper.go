package handlers

import (
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func documentOCRResponseMapper(value domain.DocumentOCR) contract.DocumentOCR {
	result := contract.DocumentOCR{Status: contract.DocumentOCRStatus(value.Status), Revision: value.Revision, Text: value.Text, SemanticIndexing: contract.DocumentOCRSemanticIndexing(value.SemanticIndexing)}
	if value.Origin != nil {
		origin := contract.DocumentOCROrigin(*value.Origin)
		result.Origin = &origin
	}
	if value.Reason != nil {
		reason := contract.DocumentOCRReason(*value.Reason)
		result.Reason = &reason
	}
	return result
}
