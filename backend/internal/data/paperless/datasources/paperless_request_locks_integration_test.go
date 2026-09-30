//go:build integration

package datasources

import (
	"context"
	"encoding/base64"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func TestPaperlessReadsAndWritesDoNotLockAuthority(t *testing.T) {
	database, err := postgres.NewPostgresDataSource(t.Context(), testdb.New(t))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(database.Close)
	if err := database.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	actor := d.DocumentActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
	tx, err := database.Database().Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	for _, query := range []struct {
		sql  string
		args []any
	}{
		{"INSERT INTO accounts(id,name) VALUES($1,'Unlocked requests')", []any{actor.AccountID}},
		{"INSERT INTO users(id,email,password_hash,personal_account_id,system_role) VALUES($1,$2,'unused',$3,'admin')", []any{actor.UserID, actor.UserID + "@example.test", actor.AccountID}},
		{"INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", []any{actor.AccountID, actor.UserID}},
		{"INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", []any{actor.SessionDigest, actor.AccountID, actor.UserID}},
	} {
		if _, err := tx.Exec(t.Context(), query.sql, query.args...); err != nil {
			t.Fatal(err)
		}
	}
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	source, err := NewPaperlessJobsDataSource(database.Database(), base64.StdEncoding.EncodeToString(make([]byte, 32)), "request-locks", nil)
	if err != nil {
		t.Fatal(err)
	}
	id, start := uuid.NewString(), make(chan struct{})
	type createResult struct {
		run m.PaperlessRun
		err error
	}
	created := make(chan createResult, 2)
	for i := 0; i < 2; i++ {
		go func() {
			<-start
			run, err := paperlessService(t, source).Create(t.Context(), actor, id, m.PaperlessConnection{ServerURL: "https://paperless.example.test", Token: "test-token"})
			created <- createResult{run, err}
		}()
	}
	close(start)
	first, second := <-created, <-created
	if first.err != nil || second.err != nil || first.run.ID != second.run.ID {
		t.Fatalf("concurrent request replay diverged: %+v %+v", first, second)
	}
	run := first.run
	for _, mode := range []string{"FOR UPDATE", "FOR NO KEY UPDATE"} {
		t.Run(mode, func(t *testing.T) {
			blocker, err := database.Database().Begin(t.Context())
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
			if mode == "FOR NO KEY UPDATE" {
				if _, err := paperlessService(t, source).Cancel(ctx, actor, run.ID); err != nil {
					t.Fatalf("cancellation waited for authority locks: %v", err)
				}
				if _, err := paperlessService(t, source).UpdateSettings(ctx, actor, m.PaperlessSettingsUpdate{ExpectedRevision: 1, RetrievalConcurrency: 2}); err != nil {
					t.Fatal(err)
				}
				return
			}
			for _, query := range []string{"SELECT id FROM paperless_runs FOR UPDATE", "SELECT singleton FROM paperless_admission FOR UPDATE"} {
				if _, err := blocker.Exec(t.Context(), query); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := paperlessService(t, source).Settings(ctx, actor); err != nil {
				t.Fatalf("settings read waited for locks: %v", err)
			}
			if _, err := paperlessService(t, source).Get(ctx, actor, run.ID); err != nil {
				t.Fatal(err)
			}
			if _, err := paperlessService(t, source).List(ctx, actor, m.PaperlessPageRequest{Limit: 20}); err != nil {
				t.Fatal(err)
			}
			if _, err := paperlessService(t, source).Outcomes(ctx, actor, run.ID, m.PaperlessPageRequest{Limit: 20}); err != nil {
				t.Fatal(err)
			}
		})
	}
}
