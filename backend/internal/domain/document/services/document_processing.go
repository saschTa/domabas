package services

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func (s *DocumentIngestionService) NamespaceConfiguration(ctx context.Context, a m.DocumentActor) (m.DocumentProcessingConfiguration, error) {
	if err := s.authorizeProcessing(ctx, a, false); err != nil {
		return m.DocumentProcessingConfiguration{}, err
	}
	v, e := s.repository.NamespaceConfiguration(ctx, a)
	if e == nil {
		v.Ready = s.processor.Ready(ctx) == nil
	}
	return v, e
}
func (s *DocumentIngestionService) Jobs(ctx context.Context, a m.DocumentActor, input m.DocumentProcessingPageInput) (m.DocumentJobPage, error) {
	principal, err := resolveDocumentAuthority(ctx, s.authority, a, identity.DocumentsJobsRead)
	if err != nil {
		return m.DocumentJobPage{}, err
	}
	return s.repository.Jobs(ctx, a, input, m.DocumentJobProjection{IncludeTitles: principal.HasPermission(identity.DocumentsRead)})
}
func (s *DocumentIngestionService) JobHistory(ctx context.Context, a m.DocumentActor, id string) (m.DocumentJobHistory, error) {
	principal, err := resolveDocumentAuthority(ctx, s.authority, a, identity.DocumentsJobsRead)
	if err != nil {
		return m.DocumentJobHistory{}, err
	}
	return s.repository.JobHistory(ctx, a, id, m.DocumentJobProjection{IncludeTitles: principal.HasPermission(identity.DocumentsRead)})
}
func (s *DocumentIngestionService) Batches(ctx context.Context, a m.DocumentActor, system bool, input m.DocumentProcessingPageInput) (m.DocumentReindexBatchPage, error) {
	if err := s.authorizeProcessing(ctx, a, system); err != nil {
		return m.DocumentReindexBatchPage{}, err
	}
	return s.repository.Batches(ctx, a, system, input)
}
func (s *DocumentIngestionService) Batch(ctx context.Context, a m.DocumentActor, system bool, id string) (m.DocumentReindexBatch, error) {
	if err := s.authorizeProcessing(ctx, a, system); err != nil {
		return m.DocumentReindexBatch{}, err
	}
	return s.repository.Batch(ctx, a, system, id)
}
func (s *DocumentIngestionService) CreateBatch(ctx context.Context, a m.DocumentActor, system bool, input m.DocumentReindexRequest) (m.DocumentReindexBatch, error) {
	claim := identity.DocumentsReindex
	if system {
		claim = identity.SystemDocumentProcessingManage
	}
	if err := s.authorize(ctx, a, claim); err != nil {
		return m.DocumentReindexBatch{}, err
	}
	if e := m.ValidateAccountID(input.RequestID); e != nil {
		return m.DocumentReindexBatch{}, e
	}
	if input.ConfigurationRevision < 1 {
		return m.DocumentReindexBatch{}, m.DocumentValidationError{Message: "configuration revision must be positive"}
	}
	for range 3 {
		facts, err := s.repository.ReindexStartFacts(ctx, a, system, input.RequestID)
		if err != nil {
			return m.DocumentReindexBatch{}, err
		}
		command, err := m.PlanDocumentReindexStart(a, system, input, facts)
		if err != nil {
			return m.DocumentReindexBatch{}, err
		}
		batch, err := s.repository.CreateBatch(ctx, a, system, command)
		if !errors.Is(err, m.ErrConflict) {
			return batch, err
		}
	}
	return m.DocumentReindexBatch{}, m.ErrConflict
}

func (s *DocumentIngestionService) RetryAI(ctx context.Context, a m.DocumentActor, id string, input m.DocumentReindexRequest) (m.DocumentAIProcessing, error) {
	if err := s.authorize(ctx, a, identity.DocumentsRetry); err != nil {
		return m.DocumentAIProcessing{}, err
	}
	if err := m.ValidateAccountID(input.RequestID); err != nil {
		return m.DocumentAIProcessing{}, err
	}
	for range 3 {
		facts, err := s.repository.AIRetryFacts(ctx, a, id, input.RequestID)
		if err != nil {
			return m.DocumentAIProcessing{}, err
		}
		command, existing, err := m.PlanDocumentAIRetry(a, id, input, facts)
		if err != nil {
			return m.DocumentAIProcessing{}, err
		}
		if existing != nil {
			return *existing, nil
		}
		result, err := s.repository.RetryAI(ctx, a, id, command)
		if !errors.Is(err, m.ErrConflict) {
			return result, err
		}
	}
	return m.DocumentAIProcessing{}, m.ErrConflict
}
