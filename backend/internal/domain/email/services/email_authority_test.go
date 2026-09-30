package services

import (
	"context"
	"errors"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type emailTestAuthority struct{ denied bool }

func (a emailTestAuthority) ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	if a.denied {
		return i.IdentityPrincipal{}, i.ErrForbidden
	}
	return i.IdentityPrincipal{CredentialRevision: 1, Permissions: []i.IdentityPermission{i.EmailManage, i.DocumentsRead, i.DocumentsUpload}}, nil
}
func (a emailTestAuthority) ResolveBackgroundAuthority(ctx context.Context, _, _ string, _ int64) (i.IdentityPrincipal, error) {
	return a.ResolveAuthority(ctx, i.IdentityPrincipal{})
}
func (*emailDiscoveryRepository) Consent(context.Context, string) (m.EmailProvider, error) {
	return m.EmailProvider{ConsentRevision: 1, EmailSettings: m.EmailSettings{Enabled: true}}, nil
}
func (*independentInspectionRepository) Consent(context.Context, string) (m.EmailProvider, error) {
	return m.EmailProvider{ConsentRevision: 1, EmailSettings: m.EmailSettings{Enabled: true}}, nil
}

func TestEmailServiceRejectsBeforeRepositoryCalls(t *testing.T) {
	service := NewEmailService(nil, nil, true, emailTestAuthority{denied: true})
	if _, err := service.Get(t.Context(), m.EmailActor{}, "id"); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
	if _, err := service.Create(t.Context(), m.EmailActor{}, m.EmailProviderInput{}); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
	if _, err := service.Start(t.Context(), m.EmailActor{}, "id", m.EmailStartRun{}); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
}

func TestEmailBackgroundDenialPreventsProviderConnection(t *testing.T) {
	service := NewEmailPollingService(&emailDiscoveryRepository{}, nil, nil, nil, nil, emailTestAuthority{denied: true})
	if _, err := service.Page(t.Context(), m.EmailAttempt{RunID: "run"}); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
}

func (*emailDiscoveryRepository) Retire(context.Context, m.EmailRetirementCommand) error { return nil }
