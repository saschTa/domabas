package services

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *DocumentIngestionService) OCR(ctx context.Context, a m.DocumentActor, id string) (m.DocumentOCR, error) {
	if err := s.authorize(ctx, a, identity.DocumentsRead, identity.DocumentsOCRRead); err != nil {
		return m.DocumentOCR{}, err
	}
	return s.repository.OCR(ctx, a, id)
}
func (s *DocumentIngestionService) CorrectOCR(ctx context.Context, a m.DocumentActor, id string, input m.DocumentOCRCorrection) (m.DocumentOCR, error) {
	if err := s.authorize(ctx, a, identity.DocumentsRead, identity.DocumentsOCRRead, identity.DocumentsOCRUpdate); err != nil {
		return m.DocumentOCR{}, err
	}
	if _, err := input.Validate(); err != nil {
		return m.DocumentOCR{}, err
	}
	for attempt := 0; attempt < 3; attempt++ {
		facts, err := s.repository.CorrectionFacts(ctx, a, id)
		if err != nil {
			return m.DocumentOCR{}, err
		}
		command, err := m.PlanDocumentCorrection(facts, input)
		if err != nil {
			return m.DocumentOCR{}, err
		}
		result, err := s.repository.CorrectOCR(ctx, a, id, command)
		if !errors.Is(err, m.ErrConflict) {
			return result, err
		}
	}
	return m.DocumentOCR{}, m.ErrConflict
}
func (s *DocumentIngestionService) Delete(ctx context.Context, a m.DocumentActor, id string) error {
	if err := s.authorize(ctx, a, identity.DocumentsRead, identity.DocumentsDelete); err != nil {
		return err
	}
	return s.repository.Delete(ctx, a, id)
}
func (s *DocumentIngestionService) reapDeleted(ctx context.Context) error {
	leases, err := s.repository.ReapDeleted(ctx, 20)
	if err != nil {
		return err
	}
	var failures []error
	for _, lease := range leases {
		ref := m.DocumentFileReference{AccountID: lease.AccountID, UploaderID: lease.UploaderID, DocumentID: lease.DocumentID, Location: "staged"}
		stagedErr := s.store.Remove(ctx, ref)
		ref.Location = "final"
		finalErr := s.store.Remove(ctx, ref)
		removeErr := errors.Join(stagedErr, finalErr)
		ackErr := s.repository.DeletedReaped(ctx, lease, m.PlanDocumentCleanup(lease, removeErr == nil, s.now().UTC()))
		if err := errors.Join(removeErr, ackErr); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}
