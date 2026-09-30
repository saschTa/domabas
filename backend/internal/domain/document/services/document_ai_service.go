package services

import (
	"context"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"time"
)

type DocumentAIService struct{ repository p.DocumentAIRepository }

func NewDocumentAIService(repository p.DocumentAIRepository) *DocumentAIService {
	return &DocumentAIService{repository}
}
func (s *DocumentAIService) Claim(ctx context.Context, limit int, lease time.Duration, queues ...string) ([]m.DocumentOutboxLease, error) {
	return s.repository.Claim(ctx, limit, lease, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), queues...)
}
func (s *DocumentAIService) Pending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error) {
	return s.repository.Pending(ctx, limit)
}
func (s *DocumentAIService) Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error {
	return s.repository.Acknowledge(ctx, l, workflow, run)
}
func (s *DocumentAIService) Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error {
	return s.repository.Release(ctx, l, next)
}
func (s *DocumentAIService) ResolveExecution(ctx context.Context, p m.DocumentPendingJob, run, code string, missing bool) error {
	if code != "" && !m.ValidFailureCode(code) {
		return m.DocumentValidationError{Message: "invalid AI execution outcome"}
	}
	facts, err := s.repository.ExecutionFacts(ctx, p)
	if err != nil {
		return err
	}
	plan, err := m.PlanDocumentExecutionRecovery(facts.RunID, run, code, missing, facts.SafeMissing)
	if err != nil {
		return err
	}
	return s.repository.ResolveExecution(ctx, p, m.DocumentExecutionResolution{ExpectedRunID: facts.RunID, RunID: run, Outcome: code, Close: plan.Close, Missing: missing})
}
func (s *DocumentAIService) Fail(ctx context.Context, j m.DocumentJob, code string) error {
	return s.repository.Fail(ctx, j, code)
}
func (s *DocumentAIService) Complete(ctx context.Context, j m.DocumentJob) error {
	facts, err := s.repository.CompletionFacts(ctx, j)
	if err != nil {
		return err
	}
	replay, err := facts.CompletionReplay()
	if err != nil || replay {
		return err
	}
	return s.repository.Complete(ctx, j, facts)
}
func (s *DocumentAIService) ReapUploads(context.Context) error { return nil }
func (s *DocumentAIService) FailExpired(ctx context.Context, j m.DocumentJob, code string) error {
	return s.repository.Fail(ctx, j, code)
}
