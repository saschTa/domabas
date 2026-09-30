//go:build integration

package datasources

import (
	"context"
	"encoding/base64"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestPaperlessConcurrentAdmissionRetainsTenAndRotatesPolling(t *testing.T) {
	url := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	if err = source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { connection.Close(context.Background()) })
	exec := func(query string, args ...any) {
		t.Helper()
		if _, err := connection.Exec(t.Context(), query, args...); err != nil {
			t.Fatal(err)
		}
	}
	for range 12 {
		account := uuid.NewString()
		owner := uuid.NewString()
		exec("BEGIN")
		exec(`INSERT INTO accounts(id,name) VALUES($1,'Concurrent imports')`, account)
		exec(`INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'test-only',$3)`, owner, owner+"@example.test", account)
		exec(`INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)`, account, owner)
		exec("COMMIT")
		exec(`INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue) VALUES($1,$2,$3,1,'https://paperless.example.test','test-only','concurrent-paperless')`, uuid.NewString(), account, owner)
	}
	scheduler := schedulersources.NewSchedulerDataSource(source.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	jobs, err := NewPaperlessJobsDataSource(source.Database(), base64.StdEncoding.EncodeToString(make([]byte, 32)), "concurrent-paperless", scheduler)
	if err != nil {
		t.Fatal(err)
	}
	type result struct {
		execution *m.PaperlessExecution
		err       error
	}
	results := make(chan result, 20)
	for range cap(results) {
		go func() {
			execution, err := jobs.Next(t.Context())
			results <- result{execution, err}
		}()
	}
	admitted := map[string]bool{}
	for range cap(results) {
		got := <-results
		if got.err != nil {
			t.Fatal(got.err)
		}
		if got.execution != nil {
			if admitted[got.execution.ID] {
				t.Fatal("duplicate Paperless polling lease")
			}
			admitted[got.execution.ID] = true
		}
	}
	if len(admitted) != 10 {
		t.Fatalf("admitted %d imports, want 10", len(admitted))
	}
	exec(`UPDATE paperless_runs SET next_check_at=clock_timestamp()-interval '1 minute' WHERE first_start_at IS NOT NULL`)
	polled := map[string]bool{}
	for range 10 {
		execution, err := jobs.Next(t.Context())
		if err != nil || execution == nil || !admitted[execution.ID] || polled[execution.ID] {
			t.Fatalf("polling starved or duplicated an import: %+v %v", execution, err)
		}
		polled[execution.ID] = true
	}
	var held string
	for id := range admitted {
		held = id
		break
	}
	if err = paperlessService(t, jobs).Finish(t.Context(), held, "cancelled", ""); err != nil {
		t.Fatal(err)
	}
	if next, err := jobs.Next(t.Context()); err != nil || next != nil {
		t.Fatalf("terminal state released unclosed capacity: %+v %v", next, err)
	}
	if err = jobs.Closed(t.Context(), held); err != nil {
		t.Fatal(err)
	}
	if next, err := jobs.Next(t.Context()); err != nil || next == nil || admitted[next.ID] {
		t.Fatalf("closure did not admit a waiting import: %+v %v", next, err)
	}
}
