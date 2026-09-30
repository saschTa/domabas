//go:build integration

package datasources

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestPaperlessRetrievalClaimsAreGlobalFencedAndRecoverable(t *testing.T) {
	url := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	db, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close(context.Background()) })
	exec := func(query string, args ...any) {
		t.Helper()
		if _, err := db.Exec(t.Context(), query, args...); err != nil {
			t.Fatal(err)
		}
	}
	newActor := func() d.DocumentActor {
		a := d.DocumentActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
		exec("BEGIN")
		exec("INSERT INTO accounts(id,name) VALUES($1,'Retrieval test')", a.AccountID)
		exec("INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'unused',$3)", a.UserID, a.UserID+"@example.test", a.AccountID)
		exec("INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", a.AccountID, a.UserID)
		exec("INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", a.SessionDigest, a.AccountID, a.UserID)
		exec("COMMIT")
		return a
	}
	a, b := newActor(), newActor()
	newJobs := func(database *postgres.PostgresDatabase) *PaperlessJobsDataSource {
		scheduler := schedulersources.NewSchedulerDataSource(database, 512, "http://ollama.test:11434")
		if err := scheduler.Initialize(t.Context()); err != nil {
			t.Fatal(err)
		}
		jobs, err := NewPaperlessJobsDataSource(database, base64.StdEncoding.EncodeToString(make([]byte, 32)), "retrieval-test", scheduler)
		if err != nil {
			t.Fatal(err)
		}
		return jobs
	}
	jobs := newJobs(source.Database())
	secondSource, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(secondSource.Close)
	secondJobs := newJobs(secondSource.Database())
	if _, err := paperlessService(t, jobs).Settings(t.Context(), a); !errors.Is(err, d.ErrForbidden) {
		t.Fatalf("namespace owner read system settings: %v", err)
	}
	if _, err := paperlessService(t, jobs).UpdateSettings(t.Context(), a, m.PaperlessSettingsUpdate{RetrievalConcurrency: 3, ExpectedRevision: 1}); !errors.Is(err, d.ErrForbidden) {
		t.Fatalf("namespace owner wrote settings: %v", err)
	}
	exec("UPDATE users SET system_role='admin' WHERE id=$1", a.UserID)
	exec("UPDATE memberships SET role='viewer',is_owner=false WHERE user_id=$1", a.UserID)
	settings, err := paperlessService(t, jobs).Settings(t.Context(), a)
	if err != nil || settings.RetrievalConcurrency != 1 || settings.Revision != 1 {
		t.Fatal(settings, err)
	}
	settings, err = paperlessService(t, jobs).UpdateSettings(t.Context(), a, m.PaperlessSettingsUpdate{RetrievalConcurrency: 3, ExpectedRevision: 1})
	if err != nil || settings.RetrievalConcurrency != 3 || settings.Revision != 2 {
		t.Fatal(settings, err)
	}
	if _, err := paperlessService(t, secondJobs).UpdateSettings(t.Context(), a, m.PaperlessSettingsUpdate{RetrievalConcurrency: 4, ExpectedRevision: 1}); !errors.Is(err, d.ErrConflict) {
		t.Fatalf("stale settings write: %v", err)
	}
	exec("UPDATE memberships SET role='admin',is_owner=true WHERE user_id=$1", a.UserID)
	runs := []string{}
	for _, actor := range []d.DocumentActor{a, b} {
		run, err := paperlessService(t, jobs).Create(t.Context(), actor, uuid.NewString(), m.PaperlessConnection{ServerURL: "https://paperless.example.test", Token: "source-token"})
		if err != nil {
			t.Fatal(err)
		}
		exec("UPDATE paperless_runs SET state='running',stage='importing' WHERE id=$1", run.ID)
		exec("INSERT INTO paperless_items(run_id,source_id,title) SELECT $1,n,'Source' FROM generate_series(1,10) n", run.ID)
		runs = append(runs, run.ID)
	}
	type result struct {
		run  string
		work m.PaperlessWork
		err  error
	}
	results := make(chan result, 8)
	for i := range 8 {
		go func() {
			adapter := jobs
			if i%2 == 1 {
				adapter = secondJobs
			}
			run := runs[i%2]
			work, err := paperlessService(t, adapter).Work(t.Context(), run)
			results <- result{run, work, err}
		}()
	}
	claims := map[string][]m.PaperlessRetrieval{}
	total := 0
	for range 8 {
		result := <-results
		if result.err != nil {
			t.Fatal(result.err)
		}
		if !result.work.Waiting {
			t.Fatal("pending work appeared complete")
		}
		claims[result.run] = append(claims[result.run], result.work.Items...)
		total += len(result.work.Items)
	}
	if total != 3 {
		t.Fatalf("global retrieval count %d, want 3", total)
	}
	settings, err = paperlessService(t, jobs).UpdateSettings(t.Context(), a, m.PaperlessSettingsUpdate{RetrievalConcurrency: 1, ExpectedRevision: 2})
	if err != nil || settings.Revision != 3 {
		t.Fatal(settings, err)
	}
	for _, run := range runs {
		work, err := paperlessService(t, jobs).Work(t.Context(), run)
		if err != nil || len(work.Items) != 0 || !work.Waiting {
			t.Fatalf("lowered limit replaced active work: %+v %v", work, err)
		}
	}
	for run, items := range claims {
		if err := jobs.ReleaseClaims(t.Context(), run, items); err != nil {
			t.Fatal(err)
		}
	}
	work, err := paperlessService(t, jobs).Work(t.Context(), runs[0])
	if err != nil || len(work.Items) != 1 {
		t.Fatal(work, err)
	}
	old := work.Items[0]
	exec("UPDATE paperless_items SET claim_deadline=clock_timestamp()-interval '1 second' WHERE run_id=$1 AND source_id=$2", runs[0], old.Document.ID)
	work, err = paperlessService(t, secondJobs).Work(t.Context(), runs[0])
	if err != nil || len(work.Items) != 0 || !work.Waiting {
		t.Fatal("recovered before drain grace", work, err)
	}
	exec("UPDATE paperless_items SET claim_deadline=clock_timestamp()-interval '2 minutes',claim_recover_after=clock_timestamp()-interval '1 minute' WHERE run_id=$1 AND source_id=$2", runs[0], old.Document.ID)
	work, err = paperlessService(t, secondJobs).Work(t.Context(), runs[0])
	if err != nil || len(work.Items) != 1 || work.Items[0].Document.ID != old.Document.ID || work.Items[0].ClaimToken == old.ClaimToken {
		t.Fatal("claim did not recover safely", work, err)
	}
	if err := jobs.RecordOutcome(t.Context(), runs[0], m.PaperlessOutcome{SourceID: old.Document.ID, ClaimToken: old.ClaimToken, Status: "duplicate"}); !errors.Is(err, d.ErrStaleJob) {
		t.Fatalf("old outcome accepted: %v", err)
	}
	if err := jobs.ReleaseClaims(t.Context(), runs[0], []m.PaperlessRetrieval{old}); err != nil {
		t.Fatal(err)
	}
	var held bool
	if err := db.QueryRow(t.Context(), "SELECT claim_token=$3::uuid FROM paperless_items WHERE run_id=$1 AND source_id=$2", runs[0], old.Document.ID, work.Items[0].ClaimToken).Scan(&held); err != nil || !held {
		t.Fatal("old owner released new claim", held, err)
	}
	if err := jobs.RecordOutcome(t.Context(), runs[0], m.PaperlessOutcome{SourceID: old.Document.ID, ClaimToken: work.Items[0].ClaimToken, Status: "duplicate"}); err != nil {
		t.Fatal(err)
	}
	if _, err := paperlessService(t, jobs).UpdateSettings(t.Context(), a, m.PaperlessSettingsUpdate{RetrievalConcurrency: 11, ExpectedRevision: 3}); err == nil {
		t.Fatal("invalid limit persisted")
	}
	exec("DELETE FROM sessions WHERE digest=$1", a.SessionDigest)
	if _, err := paperlessService(t, jobs).Settings(t.Context(), a); !errors.Is(err, d.ErrUnauthorized) {
		t.Fatalf("revoked session read settings: %v", err)
	}
}
