//go:build integration

package repos

import (
	"errors"
	"testing"
	"time"

	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func TestIdentitySessionWritesReturnStoredExpiry(t *testing.T) {
	for _, operation := range []string{"registration", "login"} {
		for _, persistent := range []bool{false, true} {
			name := operation + "/finite"
			if persistent {
				name = operation + "/persistent"
			}
			t.Run(name, func(t *testing.T) {
				pool, repository := identityFixture(t)
				session := identitySession()
				expiry := time.Now().UTC().Add(time.Hour).Truncate(time.Microsecond).Add(563 * time.Nanosecond)
				session.ExpiresAt = &expiry
				if persistent {
					session.ExpiresAt = nil
				}
				registration := newRegistration("expiry@example.test")
				registration.Session.ExpiresAt = nil
				if operation == "registration" {
					registration.Session = session
				}
				actor, err := identityRegisterFixture(t.Context(), repository, registration)
				if err != nil {
					t.Fatal(err)
				}
				credentials, err := repository.CredentialsByEmail(t.Context(), actor.Email)
				if err != nil {
					t.Fatal(err)
				}
				if operation == "login" {
					actor, err = repository.CreateSession(t.Context(), credentials, session)
					if err != nil {
						t.Fatal(err)
					}
				}
				var stored *time.Time
				if err := pool.QueryRow(t.Context(), "SELECT expires_at FROM sessions WHERE digest=$1", actor.SessionDigest).Scan(&stored); err != nil {
					t.Fatal(err)
				}
				if persistent {
					if actor.SessionExpiresAt != nil || stored != nil {
						t.Fatalf("persistent session gained an expiry: returned=%v stored=%v", actor.SessionExpiresAt, stored)
					}
				} else {
					if actor.SessionExpiresAt == nil || stored == nil || !actor.SessionExpiresAt.Equal(*stored) {
						t.Fatalf("returned expiry differs from storage: returned=%v stored=%v", actor.SessionExpiresAt, stored)
					}
					if !stored.Equal(expiry.Truncate(time.Microsecond)) {
						t.Fatalf("stored expiry changed beyond database precision: %v", stored)
					}
					if session.ExpiresAt.Nanosecond()%1000 != 563 {
						t.Fatal("session input was mutated")
					}
				}
				changed := actor
				changedExpiry := expiry.Truncate(time.Microsecond).Add(time.Microsecond)
				changed.SessionExpiresAt = &changedExpiry
				if err := repository.ChangePassword(t.Context(), changed, credentials, "new-hash", time.Now()); !errors.Is(err, identitymodels.ErrStaleFacts) {
					t.Fatalf("changed expiry was not rejected: %v", err)
				}
				if err := repository.ChangePassword(t.Context(), actor, credentials, "new-hash", time.Now()); err != nil {
					t.Fatalf("returned session cannot change password: %v", err)
				}
			})
		}
	}
}
