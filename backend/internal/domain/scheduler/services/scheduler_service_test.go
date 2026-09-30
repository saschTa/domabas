package services

import (
	"context"
	"errors"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"testing"
)

type schedulerDeniedAuthority struct{}

func (schedulerDeniedAuthority) ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	return i.IdentityPrincipal{}, i.ErrUnauthorized
}
func TestSchedulerServiceDeniesBeforeRepository(t *testing.T) {
	s := NewSchedulerService(nil, schedulerDeniedAuthority{})
	if _, err := s.Settings(t.Context(), m.SchedulerActor{}); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatal(err)
	}
	if _, err := s.UpdateSettings(t.Context(), m.SchedulerActor{}, m.SchedulerSettingsUpdate{}); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatal(err)
	}
}
