//go:build integration

package datasources

import (
	"context"
	"slices"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

func TestSchedulerCandidateBatchReconcilesOnceAndRetainsFairness(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	f.exec("UPDATE scheduler_resources SET concurrency_limit=1 WHERE id='worker'")
	running := f.paperless()
	if !f.reserve(running, "ollama") {
		t.Fatal("initial job was not admitted")
	}
	candidates := make([]m.SchedulerAdmissionCandidate, m.SchedulerMaximumAdmissionCandidates)
	for i := range candidates {
		candidates[i] = m.SchedulerAdmissionCandidate{WorkflowID: f.paperless(), Providers: []string{"ollama"}}
	}
	f.exec("CREATE TABLE scheduler_reconciliation_probe(calls integer NOT NULL)")
	f.exec("INSERT INTO scheduler_reconciliation_probe VALUES(0)")
	f.exec(`CREATE FUNCTION scheduler_reconciliation_probe() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN UPDATE scheduler_reconciliation_probe SET calls=calls+1; RETURN NULL; END $$`)
	f.exec("CREATE TRIGGER scheduler_reconciliation_probe BEFORE DELETE ON scheduler_requests FOR EACH STATEMENT EXECUTE FUNCTION scheduler_reconciliation_probe()")
	var initialJIT string
	if err := f.connection.QueryRow(t.Context(), "SHOW jit").Scan(&initialJIT); err != nil {
		t.Fatal(err)
	}
	tx, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	selected, err := f.source.ReserveFirst(t.Context(), tx, "paperless", candidates)
	if err != nil || selected != "" {
		t.Fatalf("saturated batch was admitted: %q %v", selected, err)
	}
	var jit string
	if err = tx.QueryRow(t.Context(), "SHOW jit").Scan(&jit); err != nil || jit != "off" {
		t.Fatalf("admission incurred query compilation: %q %v", jit, err)
	}
	if err = tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err = f.connection.QueryRow(t.Context(), "SHOW jit").Scan(&jit); err != nil || jit != initialJIT {
		t.Fatalf("admission changed the connection setting: %q %v", jit, err)
	}
	var calls, waiting, resources int
	if err = f.connection.QueryRow(t.Context(), `SELECT (SELECT calls FROM scheduler_reconciliation_probe),(SELECT count(*) FROM scheduler_requests WHERE state='waiting'),(SELECT count(*) FROM scheduler_request_resources r JOIN scheduler_requests q USING(workflow_id) WHERE q.state='waiting')`).Scan(&calls, &waiting, &resources); err != nil {
		t.Fatal(err)
	}
	if calls != 1 || waiting != len(candidates) || resources != 2*len(candidates) {
		t.Fatalf("batch repeated reconciliation or lost waiting ownership: calls=%d waiting=%d resources=%d", calls, waiting, resources)
	}
	f.close(running)
	oldest := candidates[0].WorkflowID
	slices.Reverse(candidates)
	tx, err = f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	selected, err = f.source.ReserveFirst(t.Context(), tx, "paperless", candidates)
	if err != nil || selected != oldest {
		t.Fatalf("candidate order displaced oldest feasible waiter: %q %v", selected, err)
	}
	if err = tx.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	var state string
	if err = f.connection.QueryRow(t.Context(), "SELECT state FROM scheduler_requests WHERE workflow_id=$1", oldest).Scan(&state); err != nil || state != "waiting" {
		t.Fatalf("rolled back admission lost waiting turn: %q %v", state, err)
	}
	if !f.reserve(oldest, "ollama") || f.active("worker") != 1 || f.active("ollama") != 1 {
		t.Fatal("rolled back candidate did not retain its resource turn")
	}
}
