//go:build integration

package repos

import (
	"context"
	"errors"
	"testing"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func TestIdentityListsDoNotWaitForAuthorityOrSetupLocks(t *testing.T) {
	database, repository := identityFixture(t)
	actor := registerIdentityUser(t, repository, "read-locks@example.test")
	invitationFor(t, repository, actor, "invitee@example.test", domain.Viewer)
	blocker, err := database.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	for _, query := range []string{
		"SELECT id FROM identity_setup FOR UPDATE",
		"SELECT id FROM accounts FOR UPDATE",
		"SELECT id FROM users FOR UPDATE",
		"SELECT user_id FROM memberships FOR UPDATE",
		"SELECT digest FROM sessions FOR UPDATE",
		"SELECT id FROM invitations FOR UPDATE",
	} {
		if _, err := blocker.Exec(t.Context(), query); err != nil {
			t.Fatal(err)
		}
	}
	checks := []struct {
		name string
		call func(context.Context) error
	}{
		{"accounts", func(ctx context.Context) error {
			_, err := identityApplication(t, repository).ListAccounts(ctx, actor, 20, 0)
			return err
		}},
		{"members", func(ctx context.Context) error {
			_, err := identityApplication(t, repository).ListMembers(ctx, actor, 20, 0)
			return err
		}},
		{"invitations", func(ctx context.Context) error {
			_, err := identityApplication(t, repository).ListInvitations(ctx, actor, 20, 0)
			return err
		}},
		{"system users", func(ctx context.Context) error {
			page, err := identityApplication(t, repository).ListSystemUsers(ctx, actor, 20, 0)
			if err == nil && (page.AdminCount != 1 || page.Total != 1 || len(page.Items) != 1) {
				t.Fatalf("inconsistent user page: %+v", page)
			}
			return err
		}},
	}
	for _, check := range checks {
		t.Run(check.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
			defer cancel()
			if err := check.call(ctx); err != nil {
				t.Fatalf("read waited for held locks: %v", err)
			}
		})
	}
	if err := blocker.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Exec(t.Context(), "DELETE FROM sessions WHERE digest=$1", actor.SessionDigest); err != nil {
		t.Fatal(err)
	}
	for _, check := range checks {
		if err := check.call(t.Context()); !errors.Is(err, domain.ErrUnauthorized) {
			t.Errorf("%s accepted revoked session: %v", check.name, err)
		}
	}
}
