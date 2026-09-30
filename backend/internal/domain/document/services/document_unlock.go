package services

import (
	"context"
	"strings"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *DocumentIngestionService) UnlockReference(ctx context.Context, a m.DocumentActor, id string, generation int64) (m.DocumentFileReference, error) {
	if err := s.authorize(ctx, a, identity.DocumentsUnlock); err != nil {
		return m.DocumentFileReference{}, err
	}
	facts, err := s.repository.UnlockFacts(ctx, a, id)
	if err != nil {
		return m.DocumentFileReference{}, err
	}
	if err = facts.Validate(generation); err != nil {
		return m.DocumentFileReference{}, err
	}
	return facts.Reference, nil
}
func (s *DocumentIngestionService) Unlock(ctx context.Context, a m.DocumentActor, id string, generation int64, password string) (m.DocumentProcessing, error) {
	if err := s.authorize(ctx, a, identity.DocumentsUnlock); err != nil {
		return m.DocumentProcessing{}, err
	}
	if generation < 1 || len(password) < 1 || len(password) > 1024 || !utf8.ValidString(password) || strings.ContainsRune(password, 0) {
		return m.DocumentProcessing{}, m.DocumentValidationError{Message: "a PDF password of 1 to 1024 bytes and a current generation are required"}
	}
	ref, err := s.UnlockReference(ctx, a, id, generation)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	reader, err := s.store.Open(ctx, ref)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	defer reader.Close()
	data, err := s.processor.UnlockPDF(ctx, reader, password)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	unlocked, err := s.store.StoreUnlocked(ctx, ref, data)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	if err := s.authorize(ctx, a, identity.DocumentsUnlock); err != nil {
		return m.DocumentProcessing{}, err
	}
	facts, err := s.repository.RetryFacts(ctx, a, id)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	command, err := m.PlanDocumentRetry(facts)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	return s.repository.CompleteUnlock(ctx, a, ref, unlocked, generation, command)
}
