package services

import (
	"context"
	"errors"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	p "github.com/domabas/domabas/backend/internal/domain/scheduler/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

type SchedulerService struct {
	repository p.SchedulerRepository
	authority  p.SchedulerAuthority
}

func NewSchedulerService(repository p.SchedulerRepository, authority p.SchedulerAuthority) *SchedulerService {
	return &SchedulerService{repository: repository, authority: authority}
}

func (s *SchedulerService) authorize(ctx context.Context, a m.SchedulerActor) error {
	if s.authority == nil {
		return m.ErrForbidden
	}
	principal, err := s.authority.ResolveAuthority(ctx, i.IdentityPrincipal{AccountID: a.AccountID, UserID: a.UserID, SessionDigest: a.SessionDigest, CredentialRevision: a.CredentialRevision})
	if errors.Is(err, i.ErrUnauthorized) {
		return m.ErrUnauthorized
	}
	if errors.Is(err, i.ErrForbidden) || errors.Is(err, i.ErrPasswordChange) {
		return m.ErrForbidden
	}
	if err != nil {
		return err
	}
	if !principal.HasPermission(i.IdentityPermission("system:workloads:manage")) {
		return m.ErrForbidden
	}
	return nil
}

func (s *SchedulerService) Settings(ctx context.Context, actor m.SchedulerActor) (m.SchedulerSettings, error) {
	if err := s.authorize(ctx, actor); err != nil {
		return m.SchedulerSettings{}, err
	}
	return s.repository.Settings(ctx, actor)
}

func (s *SchedulerService) UpdateSettings(ctx context.Context, actor m.SchedulerActor, update m.SchedulerSettingsUpdate) (m.SchedulerSettings, error) {
	if err := s.authorize(ctx, actor); err != nil {
		return m.SchedulerSettings{}, err
	}
	if err := update.Validate(); err != nil {
		return m.SchedulerSettings{}, err
	}
	current, err := s.repository.Settings(ctx, actor)
	if err != nil {
		return m.SchedulerSettings{}, err
	}
	plan, err := m.PlanSchedulerSettings(current, update)
	if err != nil {
		return m.SchedulerSettings{}, err
	}
	return s.repository.UpdateSettings(ctx, actor, plan)
}
