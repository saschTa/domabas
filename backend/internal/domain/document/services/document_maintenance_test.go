package services

import (
	"context"
	"errors"
	"testing"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type documentMaintenanceRepository struct {
	p.DocumentIngestionRepository
	aiAttempts, reindexAttempts, claims int
	failure                             error
}

func (r *documentMaintenanceRepository) AIMaintenanceFacts(context.Context) (m.DocumentAIMaintenanceFacts, error) {
	revision, cutoff := int64(2), int64(3)
	return m.DocumentAIMaintenanceFacts{Revision: &revision, Cutoff: &cutoff}, nil
}
func (r *documentMaintenanceRepository) MaintainAI(context.Context, m.DocumentAIMaintenanceCommand) error {
	r.aiAttempts++
	return r.failure
}
func (r *documentMaintenanceRepository) ReindexMaintenanceFacts(context.Context) (m.DocumentReindexMaintenanceFacts, error) {
	return m.DocumentReindexMaintenanceFacts{}, nil
}
func (r *documentMaintenanceRepository) MaintainProcessing(context.Context, m.DocumentReindexMaintenanceCommand) error {
	r.reindexAttempts++
	return r.failure
}
func (r *documentMaintenanceRepository) ReindexScheduleFacts(context.Context) ([]m.DocumentReindexScheduleFacts, error) {
	return nil, nil
}
func (r *documentMaintenanceRepository) DeliverySettings(context.Context) (m.DocumentDeliverySettings, error) {
	return m.DocumentDeliverySettings{}, nil
}
func (r *documentMaintenanceRepository) Claim(context.Context, int, time.Duration, []m.DocumentReindexScheduleCommand, m.DocumentDeliveryPolicy, ...string) ([]m.DocumentOutboxLease, error) {
	r.claims++
	return nil, nil
}

func TestMaintenanceContentionDoesNotBlockDispatch(t *testing.T) {
	repository := &documentMaintenanceRepository{failure: m.ErrConflict}
	service := NewDocumentIngestionService(repository, nil, nil, documentAllowedAuthority(), time.Now)
	if _, err := service.Claim(t.Context(), 1, time.Second); err != nil {
		t.Fatal(err)
	}
	if repository.aiAttempts != 3 || repository.reindexAttempts != 3 || repository.claims != 1 {
		t.Fatalf("unbounded or blocked maintenance: %+v", repository)
	}
}
func TestMaintenanceInfrastructureFailureStopsDispatch(t *testing.T) {
	failure := errors.New("database unavailable")
	repository := &documentMaintenanceRepository{failure: failure}
	service := NewDocumentIngestionService(repository, nil, nil, documentAllowedAuthority(), time.Now)
	if _, err := service.Claim(t.Context(), 1, time.Second); !errors.Is(err, failure) {
		t.Fatalf("lost failure: %v", err)
	}
	if repository.aiAttempts != 1 || repository.reindexAttempts != 0 || repository.claims != 0 {
		t.Fatalf("continued after infrastructure failure: %+v", repository)
	}
}
