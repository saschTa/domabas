//go:build integration

package repos

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
)

func TestEmailReadsAndWritesDoNotLockAuthority(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	for _, mode := range []string{"FOR UPDATE", "FOR NO KEY UPDATE"} {
		t.Run(mode, func(t *testing.T) {
			blocker, err := pool.Begin(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			defer blocker.Rollback(context.Background())
			for _, query := range []struct {
				sql  string
				args []any
			}{
				{"SELECT id FROM accounts WHERE id=$1 " + mode, []any{actor.AccountID}},
				{"SELECT id FROM users WHERE id=$1 " + mode, []any{actor.UserID}},
				{"SELECT user_id FROM memberships WHERE account_id=$1 AND user_id=$2 " + mode, []any{actor.AccountID, actor.UserID}},
				{"SELECT digest FROM sessions WHERE digest=$1 " + mode, []any{actor.SessionDigest}},
			} {
				if _, err := blocker.Exec(t.Context(), query.sql, query.args...); err != nil {
					t.Fatal(err)
				}
			}
			ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
			defer cancel()
			if mode == "FOR UPDATE" {
				if _, err := blocker.Exec(t.Context(), "SELECT id FROM email_providers WHERE id=$1 FOR UPDATE", provider.ID); err != nil {
					t.Fatal(err)
				}
				if _, err := source.Get(ctx, actor, provider.ID); err != nil {
					t.Fatalf("provider read waited for row locks: %v", err)
				}
				if _, _, err := source.List(ctx, actor, 20, ""); err != nil {
					t.Fatal(err)
				}
				if _, err := source.Runs(ctx, actor, m.EmailRunQuery{ProviderID: provider.ID, Limit: 20}); err != nil {
					t.Fatal(err)
				}
				return
			}
			settings := provider.EmailSettings
			settings.Label = "Independent edit"
			if _, err := independentEmailService(t, pool, repository).Update(ctx, actor, m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders, ID: provider.ID, EmailSettings: settings, ExpectedRevision: &provider.Revision}); err != nil {
				t.Fatalf("ordinary provider edit waited for authority locks: %v", err)
			}
		})
	}
}

func TestEmailProviderQuotaSerializesOneOwnerAcrossLibraries(t *testing.T) {
	pool, _, repository, actor := independentEmailFixture(t)
	for i := 0; i < 19; i++ {
		independentProvider(t, repository, actor)
	}
	other := actor
	other.AccountID, other.SessionDigest = uuid.NewString(), strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", "")
	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	for _, query := range []struct {
		sql  string
		args []any
	}{
		{"INSERT INTO accounts(id,name) VALUES($1,'Other library')", []any{other.AccountID}},
		{"INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", []any{other.AccountID, other.UserID}},
		{"INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", []any{other.SessionDigest, other.AccountID, other.UserID}},
	} {
		if _, err := tx.Exec(t.Context(), query.sql, query.args...); err != nil {
			t.Fatal(err)
		}
	}
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	start, results := make(chan struct{}), make(chan error, 2)
	for _, candidate := range []m.EmailActor{actor, other} {
		go func() {
			<-start
			username, password := "quota-user", "quota-password"
			_, err := repository.Create(t.Context(), candidate, m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders, ID: uuid.NewString(), Username: &username, Password: &password, EmailSettings: m.EmailSettings{Label: "Quota", Host: "imap.example.test", Port: 993, Mailbox: "INBOX", IntervalMinutes: 15, MaxAgeDays: 30, PageSize: 50}})
			results <- err
		}()
	}
	close(start)
	winners := 0
	for i := 0; i < 2; i++ {
		if err := <-results; err == nil {
			winners++
		} else {
			var validation m.EmailValidationError
			if !errors.As(err, &validation) || validation.Message != "at most 20 email providers are allowed" {
				t.Fatalf("unexpected quota failure: %v", err)
			}
		}
	}
	var count int
	if err := pool.QueryRow(t.Context(), "SELECT count(*) FROM email_providers WHERE owner_id=$1 AND deleted_at IS NULL", actor.UserID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if winners != 1 || count != 20 {
		t.Fatalf("owner quota raced across libraries: winners=%d providers=%d", winners, count)
	}
}
