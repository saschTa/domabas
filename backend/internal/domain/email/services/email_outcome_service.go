package services

import (
	"context"
	"errors"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func (s *EmailPollingService) PartOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, part m.EmailPart, state, code string) error {
	if err := s.authorizeRun(ctx, a.RunID); err != nil {
		return err
	}
	for range 3 {
		facts, err := s.repository.PartFacts(ctx, a, item, part)
		if err != nil {
			return err
		}
		command, err := m.PlanEmailPartOutcome(facts, a.RunID, state, code)
		if err != nil {
			return err
		}
		err = s.repository.PartOutcome(ctx, a, item, part, command)
		if !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return m.ErrConflict
}

func (s *EmailPollingService) MessageOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, state, code string, stamp *time.Time) error {
	if err := s.authorizeRun(ctx, a.RunID); err != nil {
		return err
	}
	for range 3 {
		facts, err := s.repository.MessageFacts(ctx, a, item)
		if err != nil {
			return err
		}
		command, err := m.PlanEmailMessageOutcome(facts, a.RunID, state, code, stamp)
		if err != nil {
			return err
		}
		err = s.repository.MessageOutcome(ctx, a, item, command)
		if !errors.Is(err, m.ErrConflict) {
			return err
		}
	}
	return m.ErrConflict
}

func (s *EmailPollingService) InspectionOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, complete, failures bool) error {
	if err := s.authorizeRun(ctx, a.RunID); err != nil {
		return err
	}
	return s.repository.InspectionOutcome(ctx, a, item, m.PlanEmailInspection(complete, failures))
}
