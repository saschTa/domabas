package services

import (
	"context"
	"math"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (s *DocumentIngestionService) configurationChange(ctx context.Context, current, input m.DocumentProcessingConfiguration) (m.DocumentConfigurationChange, error) {
	change := m.DocumentConfigurationChange{ExpectedRevision: current.Revision, Configuration: current}
	if input.ExpectedRevision != nil && *input.ExpectedRevision < 1 {
		return change, m.DocumentValidationError{Message: "expected revision must be positive"}
	}
	if input.LLMUpdate != nil {
		update, err := input.LLMUpdate.Normalize()
		if err != nil {
			return change, err
		}
		next := current.LLM.Defaults()
		if update.ClearAPIKey || update.Provider != next.Provider || update.BaseURL != next.BaseURL {
			next.CredentialID = ""
		}
		next.Enabled, next.Provider, next.Model, next.BaseURL = update.Enabled, update.Provider, update.Model, update.BaseURL
		if update.LMStudioCompatibility != nil {
			next.LMStudioCompatibility = *update.LMStudioCompatibility
		}
		if update.PropertyThinkingEnabled != nil {
			next.PropertyThinkingEnabled = *update.PropertyThinkingEnabled
		}
		if update.InvoiceThinkingEnabled != nil {
			next.InvoiceThinkingEnabled = *update.InvoiceThinkingEnabled
		}
		if update.ContextLength != nil {
			next.ContextLength = *update.ContextLength
		}
		invoiceEnabled := next.InvoiceExtractionEnabled()
		if update.InvoiceEnabled != nil {
			invoiceEnabled = *update.InvoiceEnabled
		}
		next.InvoiceEnabled = &invoiceEnabled
		if update.APIKey != nil {
			same := false
			if next.CredentialID != "" {
				previous, err := s.repository.ConfigurationCredential(ctx, next.CredentialID)
				if err != nil {
					return change, err
				}
				same = previous == *update.APIKey
			}
			if !same {
				id, err := documentID()
				if err != nil {
					return change, err
				}
				next.CredentialID = id
				change.Credential = &m.DocumentLLMCredentialWrite{ID: id, Key: *update.APIKey}
			}
		}
		change.Configuration.LLM = next
	}
	change.Reindex = current.Language != input.Language || current.Segmentation != input.Segmentation
	change.RescheduleAI = !current.LLM.Equal(change.Configuration.LLM)
	if !change.Reindex && !change.RescheduleAI {
		return change, nil
	}
	if input.ExpectedRevision != nil && *input.ExpectedRevision != current.Revision {
		return change, m.ErrConflict
	}
	if current.Revision == math.MaxInt64 {
		return change, m.ErrConflict
	}
	change.Configuration.Revision++
	change.Configuration.Language, change.Configuration.Segmentation = input.Language, input.Segmentation
	change.Configuration.ExpectedRevision = nil
	change.Configuration.LLMUpdate = nil
	fingerprint, err := change.Configuration.CanonicalFingerprint()
	change.Configuration.Fingerprint = fingerprint
	return change, err
}
