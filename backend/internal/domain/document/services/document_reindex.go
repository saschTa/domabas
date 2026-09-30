package services

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (s *DocumentIngestionService) MaintainProcessing(ctx context.Context) error {
	if err := s.MaintainAI(ctx); err != nil {
		return err
	}
	for range 3 {
		facts, err := s.repository.ReindexMaintenanceFacts(ctx)
		if err != nil {
			return err
		}
		if err = s.repository.MaintainProcessing(ctx, m.PlanDocumentReindexMaintenance(facts)); !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return nil
}
