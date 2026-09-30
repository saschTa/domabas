package services

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (s *DocumentIngestionService) MaintainAI(ctx context.Context) error {
	for range 3 {
		facts, err := s.repository.AIMaintenanceFacts(ctx)
		if err != nil {
			return err
		}
		if facts.Revision == nil || facts.Cutoff == nil {
			return nil
		}
		command := m.PlanDocumentAIMaintenance(facts)
		if err = s.repository.MaintainAI(ctx, command); !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return nil
}
