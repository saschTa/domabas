package services

import (
	"context"
	"errors"
	"testing"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/identity/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type identityAuthorityRepository struct {
	p.IdentityRepository
	facts m.IdentityAuthorityFacts
	err   error
	calls int
}

func (r *identityAuthorityRepository) SessionAuthority(context.Context, string) (m.IdentityAuthorityFacts, error) {
	r.calls++
	return r.facts, r.err
}
func (r *identityAuthorityRepository) BackgroundAuthority(context.Context, string, string) (m.IdentityAuthorityFacts, error) {
	r.calls++
	return r.facts, r.err
}

type identityClaimAuthorizer struct{}

func (identityClaimAuthorizer) Allows(actor m.IdentityPrincipal, permission m.IdentityPermission) bool {
	if actor.MustChangePassword {
		return false
	}
	for _, claim := range actor.Claims {
		if claim == permission {
			return true
		}
	}
	return false
}

func identityAuthorityFixture() (*IdentityService, *identityAuthorityRepository, m.IdentityPrincipal) {
	now := time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC)
	actor := m.IdentityPrincipal{UserID: "user", AccountID: "account", SessionDigest: "digest", CredentialRevision: 3, Role: m.Viewer}
	repository := &identityAuthorityRepository{facts: m.IdentityAuthorityFacts{Principal: actor, MembershipEnabled: true, SessionAccountID: actor.AccountID, SessionUserID: actor.UserID, SessionCredentialRevision: 3, ObservedAt: now}}
	return NewIdentityService(repository, &passwordSpy{}, identityClaimAuthorizer{}, func() time.Time { return now }, func() string { return "id" }), repository, actor
}

func TestResolveAuthorityUsesFreshFactsAndIgnoresCallerPermissions(t *testing.T) {
	service, repository, actor := identityAuthorityFixture()
	actor.Role, actor.SystemRole, actor.IsOwner = m.Admin, m.Admin, true
	actor.Claims = []m.IdentityPermission{m.SystemUsersManage}
	actor.Permissions = []m.IdentityPermission{m.SystemUsersManage, m.UsersManage}
	repository.facts.Principal.Claims = []m.IdentityPermission{m.DocumentsRead}
	got, err := service.ResolveAuthority(t.Context(), actor)
	if err != nil || got.HasPermission(m.SystemUsersManage) || !got.HasPermission(m.DocumentsRead) || got.IsOwner {
		t.Fatalf("fresh authority=%+v %v", got, err)
	}
}

func TestResolveAuthorityRejectsInvalidSessionFacts(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*identityAuthorityRepository, *m.IdentityPrincipal)
		want   error
	}{
		{"wrong actor account", func(_ *identityAuthorityRepository, a *m.IdentityPrincipal) { a.AccountID = "other" }, m.ErrUnauthorized},
		{"wrong actor user", func(_ *identityAuthorityRepository, a *m.IdentityPrincipal) { a.UserID = "other" }, m.ErrUnauthorized},
		{"stale actor credentials", func(_ *identityAuthorityRepository, a *m.IdentityPrincipal) { a.CredentialRevision-- }, m.ErrUnauthorized},
		{"wrong session account", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) { r.facts.SessionAccountID = "other" }, m.ErrUnauthorized},
		{"wrong session user", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) { r.facts.SessionUserID = "other" }, m.ErrUnauthorized},
		{"stale session credentials", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) { r.facts.SessionCredentialRevision-- }, m.ErrUnauthorized},
		{"expired exactly", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) {
			r.facts.Principal.SessionExpiresAt = &r.facts.ObservedAt
		}, m.ErrUnauthorized},
		{"disabled", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) { r.facts.MembershipEnabled = false }, m.ErrMembershipDisabled},
		{"forced password", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) {
			r.facts.Principal.MustChangePassword = true
		}, m.ErrPasswordChange},
		{"missing", func(r *identityAuthorityRepository, _ *m.IdentityPrincipal) { r.err = m.ErrNotFound }, m.ErrUnauthorized},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			s, r, a := identityAuthorityFixture()
			test.mutate(r, &a)
			if _, err := s.ResolveAuthority(t.Context(), a); !errors.Is(err, test.want) {
				t.Fatalf("got %v want %v", err, test.want)
			}
		})
	}
}

func TestBackgroundAuthorityRequiresRetainedRevisionWithoutSession(t *testing.T) {
	service, repository, actor := identityAuthorityFixture()
	repository.facts.Principal.SessionDigest = ""
	repository.facts.SessionUserID = ""
	for _, revision := range []int64{0, -1, 2, 4} {
		if _, err := service.ResolveBackgroundAuthority(t.Context(), actor.AccountID, actor.UserID, revision); !errors.Is(err, m.ErrUnauthorized) {
			t.Fatalf("revision %d: %v", revision, err)
		}
	}
	got, err := service.ResolveBackgroundAuthority(t.Context(), actor.AccountID, actor.UserID, 3)
	if err != nil || got.SessionDigest != "" {
		t.Fatalf("background identity=%+v %v", got, err)
	}
	repository.facts.MembershipEnabled = false
	if _, err := service.ResolveBackgroundAuthority(t.Context(), actor.AccountID, actor.UserID, 3); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("disabled background: %v", err)
	}
}

func TestIdentityProtectedServiceMethodsDenyBeforeRepositoryMutation(t *testing.T) {
	cases := []struct {
		name string
		call func(*IdentityService, m.IdentityPrincipal) error
	}{
		{"create member", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.CreateMember(t.Context(), a, "new@example.test", "Valid password 123", m.User, nil)
			return e
		}},
		{"update member", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.UpdateMember(t.Context(), a, "target", m.User, nil, true)
			return e
		}},
		{"list members", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.ListMembers(t.Context(), a, 10, 0)
			return e
		}},
		{"create invitation", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.CreateInvitation(t.Context(), a, "new@example.test", m.User, nil)
			return e
		}},
		{"list invitations", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.ListInvitations(t.Context(), a, 10, 0)
			return e
		}},
		{"revoke invitation", func(s *IdentityService, a m.IdentityPrincipal) error {
			return s.RevokeInvitation(t.Context(), a, "target")
		}},
		{"system users", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.ListSystemUsers(t.Context(), a, 10, 0)
			return e
		}},
		{"system mutation", func(s *IdentityService, a m.IdentityPrincipal) error {
			_, e := s.UpdateSystemUser(t.Context(), a, "target", m.Admin)
			return e
		}},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			service, repository, actor := identityAuthorityFixture()
			actor.Permissions = []m.IdentityPermission{m.UsersManage, m.SystemUsersManage}
			if err := test.call(service, actor); !errors.Is(err, m.ErrForbidden) {
				t.Fatal(err)
			}
			if repository.calls != 1 {
				t.Fatalf("authority calls=%d", repository.calls)
			}
		})
	}
}

type identityAdminRepository struct {
	*identityAuthorityRepository
	snapshots     []m.IdentitySystemUserFacts
	reads, writes int
}

func (r *identityAdminRepository) SystemUserFacts(context.Context, string) (m.IdentitySystemUserFacts, error) {
	v := r.snapshots[r.reads]
	r.reads++
	return v, nil
}
func (r *identityAdminRepository) UpdateSystemUser(context.Context, m.IdentityPrincipal, m.IdentitySystemUserFacts, m.IdentityRole) (m.SystemUser, error) {
	r.writes++
	return m.SystemUser{}, m.ErrStaleFacts
}
func TestAdministratorRetryReloadsDecisionBeforeWritingAgain(t *testing.T) {
	service, authority, actor := identityAuthorityFixture()
	authority.facts.Principal.Claims = []m.IdentityPermission{m.SystemUsersManage}
	target := m.SystemUser{ID: "target", Role: m.Admin}
	repository := &identityAdminRepository{identityAuthorityRepository: authority, snapshots: []m.IdentitySystemUserFacts{{Target: target, Installation: m.IdentityInstallationFacts{AdministratorIDs: []string{"target", "other"}}}, {Target: target, Installation: m.IdentityInstallationFacts{AdministratorIDs: []string{"target"}}}}}
	service.repository = repository
	if _, err := service.UpdateSystemUser(t.Context(), actor, target.ID, m.User); !errors.Is(err, m.ErrConflict) {
		t.Fatal(err)
	}
	if repository.reads != 2 || repository.writes != 1 {
		t.Fatalf("reads=%d writes=%d", repository.reads, repository.writes)
	}
}

func TestResolveAuthorityIgnoresCallerSuppliedThumbnailPermissions(t *testing.T) {
	service, repository, actor := identityAuthorityFixture()
	actor.Role, actor.SystemRole, actor.IsOwner = m.Admin, m.Admin, true
	actor.Claims = []m.IdentityPermission{m.DocumentsThumbnailsRead, m.DocumentsDownload}
	actor.Permissions = []m.IdentityPermission{m.DocumentsThumbnailsRead, m.DocumentsDownload}
	repository.facts.Principal.Claims = []m.IdentityPermission{m.DocumentsRead}
	current, err := service.ResolveAuthority(t.Context(), actor)
	if err != nil || current.HasPermission(m.DocumentsThumbnailsRead) || current.HasPermission(m.DocumentsDownload) || !current.HasPermission(m.DocumentsRead) {
		t.Fatalf("caller thumbnail permissions escaped current facts: %+v %v", current, err)
	}
}
