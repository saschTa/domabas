//go:build integration

package datasources

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestPaperlessHistoryAndOutcomesContinuePastLegacyLimits(t *testing.T) {
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
		a := d.DocumentActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
		exec("BEGIN")
		exec("INSERT INTO accounts(id,name) VALUES($1,'Paged imports')", a.AccountID)
		exec("INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'unused',$3)", a.UserID, a.UserID+"@example.test", a.AccountID)
		exec("INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", a.AccountID, a.UserID)
		exec("INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", a.SessionDigest, a.AccountID, a.UserID)
		exec("COMMIT")
		return a
	}
	a, other := actor(), actor()
	scheduler := schedulersources.NewSchedulerDataSource(source.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	jobs, err := NewPaperlessJobsDataSource(source.Database(), base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32)), "pagination-test", scheduler)
	if err != nil {
		t.Fatal(err)
	}
	created := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	insert := func(id string, a d.DocumentActor, at time.Time) {
		exec("INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue,state,stage,execution_closed,created_at) VALUES($1,$2,$3,1,'https://example.test','test','pagination-test','succeeded','complete',true,$4)", id, a.AccountID, a.UserID, at)
	}
	for i := 1; i <= 25; i++ {
		insert(fmt.Sprintf("00000000-0000-4000-8000-%012d", i), a, created)
	}
	insert(uuid.NewString(), other, created)
	exec("INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", a.AccountID, other.UserID)
	sharedOther := other
	sharedOther.AccountID = a.AccountID
	insert(uuid.NewString(), sharedOther, created)
	first, err := paperlessService(t, jobs).List(t.Context(), a, m.PaperlessPageRequest{Limit: 20})
	if err != nil || len(first.Items) != 20 || first.NextCursor == "" {
		t.Fatalf("first: %+v %v", first, err)
	}
	if len(first.Counts) != 1 || first.Counts[0].Status != "succeeded" || first.Counts[0].Count != 25 {
		t.Fatalf("counts leaked owner/namespace or used page length: %v", first.Counts)
	}
	if first.Items[0].ID != "00000000-0000-4000-8000-000000000025" {
		t.Fatal("unstable tie order")
	}
	insert(uuid.NewString(), a, created.Add(time.Minute))
	second, err := paperlessService(t, jobs).List(t.Context(), a, m.PaperlessPageRequest{Limit: 20, Cursor: first.NextCursor})
	if err != nil || len(second.Items) != 5 || second.NextCursor != "" {
		t.Fatalf("second: %+v %v", second, err)
	}
	seen := map[string]bool{}
	for _, item := range append(first.Items, second.Items...) {
		if seen[item.ID] || len(item.Outcomes) != 0 {
			t.Fatal("repeated job or eagerly loaded outcomes")
		}
		seen[item.ID] = true
	}
	for _, page := range []m.PaperlessPageRequest{{Limit: 0}, {Limit: 101}, {Limit: 20, Cursor: "invalid"}, {Limit: 19, Cursor: first.NextCursor}} {
		if _, err := paperlessService(t, jobs).List(t.Context(), a, page); err == nil {
			t.Fatalf("accepted invalid page: %+v", page)
		}
	}
	if _, err := paperlessService(t, jobs).List(t.Context(), other, m.PaperlessPageRequest{Limit: 20, Cursor: first.NextCursor}); err == nil {
		t.Fatal("accepted foreign cursor")
	}
	runID := first.Items[0].ID
	exec("INSERT INTO paperless_items(run_id,source_id,title,status) SELECT $1,n,'Result '||n,'failed' FROM generate_series(1,115) n", runID)
	partial, err := paperlessService(t, jobs).List(t.Context(), a, m.PaperlessPageRequest{Limit: 1, Status: "partial"})
	if err != nil || len(partial.Items) != 1 {
		t.Fatalf("partial: %+v %v", partial, err)
	}
	counts := map[string]int64{}
	for _, group := range partial.Counts {
		counts[group.Status] = group.Count
	}
	if counts["partial"] != 1 || counts["succeeded"] != 25 {
		t.Fatalf("partial count lost effective state or other statuses: %v", counts)
	}
	page, err := paperlessService(t, jobs).Outcomes(t.Context(), a, runID, m.PaperlessPageRequest{Limit: 20})
	if err != nil || len(page.Items) != 20 || page.NextCursor == "" {
		t.Fatalf("outcomes: %+v %v", page, err)
	}
	if _, err := paperlessService(t, jobs).Outcomes(t.Context(), other, runID, m.PaperlessPageRequest{Limit: 20}); !errors.Is(err, d.ErrNotFound) {
		t.Fatal("foreign outcomes", err)
	}
	if _, err := paperlessService(t, jobs).Outcomes(t.Context(), a, first.Items[1].ID, m.PaperlessPageRequest{Limit: 20, Cursor: page.NextCursor}); err == nil {
		t.Fatal("accepted another run's cursor")
	}
	if _, err := paperlessService(t, jobs).List(t.Context(), a, m.PaperlessPageRequest{Limit: 20, Cursor: page.NextCursor}); err == nil {
		t.Fatal("accepted another operation's cursor")
	}
	count, last := 0, int64(116)
	for {
		for _, item := range page.Items {
			if item.SourceID >= last {
				t.Fatal("outcome order or duplicate")
			}
			last = item.SourceID
			count++
		}
		if page.NextCursor == "" {
			break
		}
		page, err = paperlessService(t, jobs).Outcomes(t.Context(), a, runID, m.PaperlessPageRequest{Limit: 20, Cursor: page.NextCursor})
		if err != nil {
			t.Fatal(err)
		}
	}
	if count != 115 || last != 1 {
		t.Fatalf("incomplete outcomes: %d, last %d", count, last)
	}
	exec("INSERT INTO paperless_items(run_id,source_id,title,status) SELECT $1,n,'Imported','imported' FROM generate_series(116,150) n", runID)
	exec("INSERT INTO paperless_items(run_id,source_id,title,status) VALUES($1,151,'Duplicate','duplicate'),($1,152,'Pending','pending')", runID)
	unfiltered, err := paperlessService(t, jobs).Outcomes(t.Context(), a, runID, m.PaperlessPageRequest{Limit: 20})
	if err != nil || len(unfiltered.Items) != 20 || unfiltered.Items[19].Status == "failed" {
		t.Fatalf("mixed outcomes: %+v %v", unfiltered, err)
	}
	failed, err := paperlessService(t, jobs).Outcomes(t.Context(), a, runID, m.PaperlessPageRequest{Limit: 20, Status: "failed"})
	if err != nil || len(failed.Items) != 20 || failed.Items[0].SourceID != 115 || failed.NextCursor == "" {
		t.Fatalf("failed outcomes beyond first page: %+v %v", failed, err)
	}
	for _, request := range []m.PaperlessPageRequest{
		{Limit: 20, Cursor: failed.NextCursor},
		{Limit: 20, Status: "imported", Cursor: failed.NextCursor},
		{Limit: 20, Status: "failed", Cursor: unfiltered.NextCursor},
		{Limit: 20, Status: "running"},
		{Limit: 20, Status: "pending"},
	} {
		if _, err := paperlessService(t, jobs).Outcomes(t.Context(), a, runID, request); err == nil {
			t.Fatalf("accepted invalid filtered page: %+v", request)
		}
	}
	filteredCursor := failed.NextCursor
	count = 0
	for {
		for _, item := range failed.Items {
			if item.Status != "failed" {
				t.Fatal("filter returned another outcome status", item)
			}
			count++
		}
		if failed.NextCursor == "" {
			break
		}
		failed, err = paperlessService(t, jobs).Outcomes(t.Context(), a, runID, m.PaperlessPageRequest{Limit: 20, Status: "failed", Cursor: failed.NextCursor})
		if err != nil {
			t.Fatal(err)
		}
	}
	if count != 115 {
		t.Fatalf("incomplete filtered results: %d", count)
	}
	if _, err := paperlessService(t, jobs).Outcomes(t.Context(), other, runID, m.PaperlessPageRequest{Limit: 20, Status: "failed", Cursor: filteredCursor}); !errors.Is(err, d.ErrNotFound) {
		t.Fatal("foreign filtered outcomes", err)
	}
	exec("UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2", a.AccountID, a.UserID)
	if _, err := paperlessService(t, jobs).Outcomes(t.Context(), a, runID, m.PaperlessPageRequest{Limit: 20, Status: "failed", Cursor: filteredCursor}); !errors.Is(err, d.ErrForbidden) {
		t.Fatal("filtered cursor bypassed revoked membership", err)
	}
	if _, err := paperlessService(t, jobs).List(t.Context(), a, m.PaperlessPageRequest{Limit: 20, Cursor: first.NextCursor}); !errors.Is(err, d.ErrForbidden) {
		t.Fatal("cursor bypassed revoked membership", err)
	}
}
