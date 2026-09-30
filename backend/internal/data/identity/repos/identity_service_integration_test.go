//go:build integration

package repos

import (
	"context"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/identity/security"
	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	s "github.com/domabas/domabas/backend/internal/domain/identity/services"
	"github.com/google/uuid"
)

type identityFixturePasswords struct{}

func (identityFixturePasswords) Hash(_ context.Context, password string) (string, error) {
	return password, nil
}
func (identityFixturePasswords) Verify(_ context.Context, password, hash string) (bool, error) {
	return password == hash, nil
}
func (identityFixturePasswords) Dummy(context.Context, string) error { return nil }

func identityApplication(t *testing.T, repository *IdentityRepository) *s.IdentityService {
	t.Helper()
	policy, err := security.NewCasbinIdentityAuthorizer()
	if err != nil {
		t.Fatal(err)
	}
	return s.NewIdentityService(repository, identityFixturePasswords{}, policy, time.Now, uuid.NewString)
}

func identityRegisterFixture(ctx context.Context, repository *IdentityRepository, input m.IdentityRegistration) (m.IdentityPrincipal, error) {
	facts, err := repository.InstallationFacts(ctx)
	if err != nil {
		return m.IdentityPrincipal{}, err
	}
	input.ExpectedSetupEligible, input.ConsumeSetup = facts.BootstrapEligible, facts.BootstrapEligible
	input.SystemRole = m.User
	if facts.BootstrapEligible {
		input.SystemRole = m.Admin
	}
	return repository.Register(ctx, input)
}

func identityCreateMemberFixture(t *testing.T, repository *IdentityRepository, ctx context.Context, actor m.IdentityPrincipal, input m.IdentityNewMember, _ time.Time) (m.IdentityMember, error) {
	return identityApplication(t, repository).CreateMember(ctx, actor, input.Email, "Fixture password 123!", input.Role, input.Claims)
}

func identitySwitchFixture(t *testing.T, repository *IdentityRepository, ctx context.Context, actor m.IdentityPrincipal, account string, _ m.IdentitySessionRecord) (m.IdentityPrincipal, *time.Time, error) {
	session, err := identityApplication(t, repository).SwitchAccount(ctx, actor, account)
	return session.Identity, session.ExpiresAt, err
}

func identityAuthenticateFixture(t *testing.T, repository *IdentityRepository, ctx context.Context, digest string, _ time.Time) (m.IdentityPrincipal, error) {
	facts, err := repository.SessionAuthority(ctx, digest)
	if err != nil {
		return m.IdentityPrincipal{}, m.ErrUnauthorized
	}
	return identityApplication(t, repository).ResolveAuthority(ctx, facts.Principal)
}
