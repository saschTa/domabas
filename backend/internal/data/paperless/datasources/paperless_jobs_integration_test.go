//go:build integration

package datasources

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestDurableJobsEncryptIsolateCheckpointAndSerializeAdmission(t *testing.T) {
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
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := db.Exec(t.Context(), sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	actor := func() d.DocumentActor {
		exec("BEGIN")
		a := d.DocumentActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
		exec("INSERT INTO accounts(id,name) VALUES($1,'Paperless test')", a.AccountID)
		exec("INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'unused',$3)", a.UserID, a.UserID+"@example.test", a.AccountID)
		exec("INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", a.AccountID, a.UserID)
		exec("INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", a.SessionDigest, a.AccountID, a.UserID)
		exec("COMMIT")
		return a
	}
	a, b := actor(), actor()
	keyPath := filepath.Join(t.TempDir(), "secrets", "paperless.key")
	key, err := CredentialKey(t.Context(), source.Database(), "", keyPath)
	if err != nil {
		t.Fatal(err)
	}
	scheduler := schedulersources.NewSchedulerDataSource(source.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	jobs, err := NewPaperlessJobsDataSource(source.Database(), key, "test-owned-queue", scheduler)
	if err != nil {
		t.Fatal(err)
	}
	connection := m.PaperlessConnection{ServerURL: "https://paperless.example.test", Token: "private-test-token"}
	id := uuid.NewString()
	run, err := paperlessService(t, jobs).Create(t.Context(), a, id, connection)
	if err != nil || run.State != "queued" {
		t.Fatal(run, err)
	}
	var encrypted []byte
	if err := db.QueryRow(t.Context(), "SELECT encrypted_token FROM paperless_runs WHERE id=$1", id).Scan(&encrypted); err != nil || bytes.Contains(encrypted, []byte(connection.Token)) {
		t.Fatal("credential not encrypted", err)
	}
	retained, err := CredentialKey(t.Context(), source.Database(), "", keyPath)
	if err != nil || retained != key {
		t.Fatal("restart did not preserve credentials", err)
	}
	wrongKey := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	if _, err := CredentialKey(t.Context(), source.Database(), wrongKey, keyPath); err == nil {
		t.Fatal("wrong override key accepted with retained jobs")
	}
	if err := os.Rename(keyPath, keyPath+".backup"); err != nil {
		t.Fatal(err)
	}
	if _, err := CredentialKey(t.Context(), source.Database(), "", keyPath); err == nil {
		t.Fatal("missing active key was regenerated")
	}
	if _, err := os.Stat(keyPath); !os.IsNotExist(err) {
		t.Fatal("missing active key was written", err)
	}
	if err := os.Rename(keyPath+".backup", keyPath); err != nil {
		t.Fatal(err)
	}
	if _, err := paperlessService(t, jobs).Create(t.Context(), a, id, connection); err != nil {
		t.Fatal("idempotent replay", err)
	}
	changed := connection
	changed.Token = "replacement"
	if _, err := paperlessService(t, jobs).Create(t.Context(), a, id, changed); !errors.Is(err, d.ErrConflict) {
		t.Fatal("changed request was accepted", err)
	}
	if _, err := paperlessService(t, jobs).Create(t.Context(), a, uuid.NewString(), connection); !errors.Is(err, d.ErrConflict) {
		t.Fatal("duplicate active job", err)
	}
	secondConnection := m.PaperlessConnection{ServerURL: "http://other-paperless.example.test:8000/source/", Token: "another-private-token"}
	second, err := paperlessService(t, jobs).Create(t.Context(), b, uuid.NewString(), secondConnection)
	if err != nil {
		t.Fatal(err)
	}
	if second.ServerURL != "http://other-paperless.example.test:8000/source" {
		t.Fatal("user source was not normalized and retained", second.ServerURL)
	}
	c := actor()
	queued, err := paperlessService(t, jobs).Create(t.Context(), c, uuid.NewString(), connection)
	if err != nil {
		t.Fatal(err)
	}
	queued, err = paperlessService(t, jobs).Cancel(t.Context(), c, queued.ID)
	if err != nil || queued.State != "cancelled" || !queued.CancelRequested {
		t.Fatal("queued cancellation was deferred", queued, err)
	}
	var erased, closed, neverAdmitted bool
	if err := db.QueryRow(t.Context(), "SELECT encrypted_token IS NULL,execution_closed,first_start_at IS NULL FROM paperless_runs WHERE id=$1", queued.ID).Scan(&erased, &closed, &neverAdmitted); err != nil || !erased || !closed || !neverAdmitted {
		t.Fatal("queued cancellation retained work or credentials", err, erased, closed, neverAdmitted)
	}
	if _, err := paperlessService(t, jobs).Get(t.Context(), b, id); !errors.Is(err, d.ErrNotFound) {
		t.Fatal("foreign job disclosed", err)
	}
	if _, err := paperlessService(t, jobs).Cancel(t.Context(), b, id); !errors.Is(err, d.ErrNotFound) {
		t.Fatal("foreign cancellation", err)
	}
	var wg sync.WaitGroup
	admissions := make(chan string, 8)
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			next, err := jobs.Next(t.Context())
			if err != nil {
				t.Error(err)
			} else if next != nil {
				admissions <- next.ID
			}
		}()
	}
	wg.Wait()
	close(admissions)
	seen := map[string]bool{}
	for admitted := range admissions {
		if seen[admitted] {
			t.Fatal("duplicate polling lease", admitted)
		}
		seen[admitted] = true
	}
	if len(seen) != 2 || !seen[id] || !seen[second.ID] {
		t.Fatal("independent imports were not admitted", seen)
	}
	w, err := paperlessService(t, jobs).Work(t.Context(), id)
	if err != nil || w.Connection.Token != connection.Token || w.Actor.ImportRunID != id {
		t.Fatal("cannot restore checkpoint", w, err)
	}
	page := m.PaperlessPage{Total: 2, Items: []m.PaperlessDocument{{ID: 1, Title: "One"}}, HasMore: true}
	if err := paperlessService(t, jobs).RecordPage(t.Context(), id, 1, page); err != nil {
		t.Fatal(err)
	}
	if err := paperlessService(t, jobs).RecordPage(t.Context(), id, 1, page); err != nil {
		t.Fatal("page replay", err)
	}
	page.Items = []m.PaperlessDocument{{ID: 2, Title: "Two"}}
	page.HasMore = false
	if err := paperlessService(t, jobs).RecordPage(t.Context(), id, 2, page); err != nil {
		t.Fatal(err)
	}
	w, err = paperlessService(t, jobs).Work(t.Context(), id)
	if err != nil || len(w.Items) != 1 || w.Items[0].Document.ID != 1 {
		t.Fatal(w, err)
	}
	outcome := m.PaperlessOutcome{SourceID: 1, Status: "duplicate", ClaimToken: w.Items[0].ClaimToken}
	if err := jobs.RecordOutcome(t.Context(), id, outcome); err != nil {
		t.Fatal(err)
	}
	if err := jobs.RecordOutcome(t.Context(), id, outcome); err != nil {
		t.Fatal(err)
	}
	if _, err := paperlessService(t, jobs).Cancel(t.Context(), a, id); err != nil {
		t.Fatal(err)
	}
	w, err = paperlessService(t, jobs).Work(t.Context(), id)
	if err != nil || !w.Run.CancelRequested {
		t.Fatal(w, err)
	}
	if err := paperlessService(t, jobs).Finish(t.Context(), id, "cancelled", ""); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(t.Context(), "SELECT encrypted_token FROM paperless_runs WHERE id=$1", id).Scan(&encrypted); err != nil || encrypted != nil {
		t.Fatal("terminal secret retained", err)
	}
	exec("UPDATE paperless_runs SET next_check_at=clock_timestamp()-interval '1 hour' WHERE id=$1", id)
	next, err := jobs.Next(t.Context())
	if err != nil || next == nil || next.ID != id {
		t.Fatal("released before Temporal closure", next, err)
	}
	if err := jobs.Closed(t.Context(), id); err != nil {
		t.Fatal(err)
	}
	exec("UPDATE paperless_runs SET next_check_at=clock_timestamp()-interval '1 hour' WHERE id=$1", second.ID)
	next, err = jobs.Next(t.Context())
	if err != nil || next == nil || next.ID != second.ID {
		t.Fatal(next, err)
	}
	exec("UPDATE users SET credential_revision=credential_revision+1 WHERE id=$1", b.UserID)
	if _, err := paperlessService(t, jobs).Work(t.Context(), second.ID); !errors.Is(err, d.ErrForbidden) {
		t.Fatal("revoked background consent", err)
	}
	large, err := paperlessService(t, jobs).Create(t.Context(), c, uuid.NewString(), connection)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := paperlessService(t, jobs).Work(t.Context(), large.ID); err != nil {
		t.Fatal(err)
	}
	exec("INSERT INTO paperless_items(run_id,source_id,title) SELECT $1,n,'Source document' FROM generate_series(1,10000) n", large.ID)
	exec("UPDATE paperless_runs SET page=101,source_total=10002 WHERE id=$1", large.ID)
	if err := paperlessService(t, jobs).RecordPage(t.Context(), large.ID, 101, m.PaperlessPage{Total: 10002, Items: []m.PaperlessDocument{{ID: 10001, Title: "Past old limit"}}, HasMore: true}); err != nil {
		t.Fatal("large library checkpoint rejected", err)
	}
	if err := paperlessService(t, jobs).RecordPage(t.Context(), large.ID, 102, m.PaperlessPage{Total: 10002, Items: []m.PaperlessDocument{{ID: 10002, Title: "Final document"}}}); err != nil {
		t.Fatal("large library final page rejected", err)
	}
	large, err = paperlessService(t, jobs).Get(t.Context(), c, large.ID)
	if err != nil || large.Discovered != 10002 || large.Stage != "importing" {
		t.Fatal("large library did not reach import stage", large, err)
	}
	exec("UPDATE paperless_items SET status='duplicate' WHERE run_id=$1 AND source_id<=10000", large.ID)
	w, err = paperlessService(t, jobs).Work(t.Context(), large.ID)
	if err != nil || len(w.Items) != 1 || w.Items[0].Document.ID != 10001 {
		t.Fatal("large library checkpoint did not skip completed items", w, err)
	}
	t.Run("status filters run before pagination", func(t *testing.T) {
		for _, status := range []string{"succeeded", "failed", "partial"} {
			state := status
			if status == "partial" {
				state = "succeeded"
			}
			for range 3 {
				runID := uuid.NewString()
				exec(`INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue,state,stage,execution_closed,created_at)
SELECT $2,account_id,owner_id,credential_revision,server_url,request_hash,task_queue,$3,'complete',true,'2000-01-01' FROM paperless_runs WHERE id=$1`, id, runID, state)
				if status == "partial" {
					exec("INSERT INTO paperless_items(run_id,source_id,title,status) VALUES($1,1,'Failed file','failed')", runID)
				}
			}
			q := m.PaperlessPageRequest{Limit: 2, Status: status}
			first, err := paperlessService(t, jobs).List(t.Context(), a, q)
			if err != nil || len(first.Items) != 2 || first.NextCursor == "" {
				t.Fatalf("first %s page: %+v %v", status, first, err)
			}
			q.Cursor = first.NextCursor
			next, err := paperlessService(t, jobs).List(t.Context(), a, q)
			if err != nil || len(next.Items) != 1 || next.NextCursor != "" || next.Items[0].ID == first.Items[1].ID {
				t.Fatalf("next %s page: %+v %v", status, next, err)
			}
			for _, run := range append(first.Items, next.Items...) {
				if run.State != state || (status == "partial") != (run.Failed > 0) {
					t.Fatalf("wrong status: %+v", run)
				}
			}
			q.Status = "queued"
			if _, err := paperlessService(t, jobs).List(t.Context(), a, q); err == nil {
				t.Fatal("cursor accepted after status changed")
			}
		}
		page, err := paperlessService(t, jobs).List(t.Context(), a, m.PaperlessPageRequest{Limit: 10, Status: "succeeded"})
		if err != nil || len(page.Items) != 3 {
			t.Fatalf("partial runs included in success: %+v %v", page, err)
		}
	})
}
