package services

import (
	"context"
	"errors"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentInitializationService struct {
	repository p.DocumentInitializationRepository
}

func NewDocumentInitializationService(repository p.DocumentInitializationRepository) *DocumentInitializationService {
	return &DocumentInitializationService{repository: repository}
}
func (s *DocumentInitializationService) Initialize(ctx context.Context) error {
	for range 3 {
		facts, err := s.repository.InitializationFacts(ctx)
		if err != nil {
			return err
		}
		command, err := m.PlanDocumentInitialization(facts)
		if err != nil {
			return err
		}
		if command.Noop {
			return nil
		}
		if command.CheckDrift {
			command.Drift, err = s.repository.InitializationDrift(ctx, command.Configuration.Fingerprint)
			if err != nil {
				return err
			}
			if command.Drift {
				command.BatchReason = "adoption"
			}
		}
		if err = s.repository.InitializeConfiguration(ctx, command); !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return m.ErrConflict
}
