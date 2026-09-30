//go:build integration

package datasources

import (
	"bytes"
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
)

func TestSchedulerSettingsSavesDuringManyRunningAIJobs(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	const provider = "https://inference.example.test"
	resourceID := f.source.ResourceID(provider)
	f.exec(`UPDATE scheduler_resources SET concurrency_limit=256 WHERE id='worker'`)
	f.exec(`INSERT INTO scheduler_resources(id,label,origin,concurrency_limit) VALUES($1,$2,$2,256)`, resourceID, provider)
	f.exec(`UPDATE document_processing_configuration SET scheduler_provider='openai',scheduler_base_url=$1`, provider)
	f.exec(`INSERT INTO document_ai_jobs(account_id,document_id,generation,attempt,ocr_revision,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,workflow_id,admitted_at,closed_at)
 SELECT $1,md5(n::text)::uuid,1,1,0,'upload',1,'test','{}',
 CASE WHEN n<=256 THEN 'running' WHEN n<=100256 THEN 'succeeded' ELSE 'queued' END,
 CASE WHEN n<=256 THEN 'enriching' WHEN n<=100256 THEN 'complete' ELSE 'queued' END,'machine',
 CASE WHEN n<=100256 THEN 'document-ai-v1/'||$1::uuid::text||'/'||md5(n::text)::uuid::text||'/1/1' ELSE '' END,
 CASE WHEN n<=100256 THEN clock_timestamp() END,
 CASE WHEN n>256 AND n<=100256 THEN clock_timestamp() END
 FROM generate_series(1,100276) n`, actor.AccountID)
	f.exec(`INSERT INTO scheduler_requests(workflow_id,pipeline,state,admitted_at)
 SELECT 'document-ai-v1/'||account_id::text||'/'||document_id::text||'/1/1','document_ai',
 CASE WHEN status='running' THEN 'active' WHEN closed_at IS NOT NULL THEN 'released' ELSE 'waiting' END,admitted_at
 FROM document_ai_jobs ORDER BY created_at,id`)
	f.exec(`INSERT INTO scheduler_request_resources(workflow_id,resource_id)
 SELECT workflow_id,r.id FROM scheduler_requests CROSS JOIN scheduler_resources r WHERE r.id IN ('worker',$1)`, resourceID)
	for _, table := range []string{"document_ai_jobs", "scheduler_requests", "scheduler_request_resources"} {
		f.exec("ANALYZE " + table)
	}
	var plan []byte
	if err := f.connection.QueryRow(t.Context(), `EXPLAIN (FORMAT JSON) SELECT q.workflow_id FROM scheduler_requests q WHERE q.state='active' AND NOT `+schedulerClosedExecution).Scan(&plan); err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(plan, []byte(`"Index Name": "document_ai_jobs_closed_workflow_idx"`)) {
		t.Fatalf("active AI ownership lookup scans retained history: %s", plan)
	}
	settings, err := f.service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	rows, err := f.connection.Query(t.Context(), `SELECT workflow_id FROM scheduler_requests WHERE state='waiting' ORDER BY sequence`)
	if err != nil {
		t.Fatal(err)
	}
	var candidates []m.SchedulerAdmissionCandidate
	for rows.Next() {
		var workflowID string
		if err := rows.Scan(&workflowID); err != nil {
			t.Fatal(err)
		}
		candidates = append(candidates, m.SchedulerAdmissionCandidate{WorkflowID: workflowID, Providers: []string{provider}})
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	admission, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer admission.Rollback(context.Background())
	selected, err := f.source.ReserveFirst(t.Context(), admission, "document_ai", candidates)
	if err != nil || selected != "" {
		t.Fatalf("saturated provider admitted a new job: %q %v", selected, err)
	}
	var admissionPID int32
	if err := admission.QueryRow(t.Context(), "SELECT pg_backend_pid()").Scan(&admissionPID); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	update := m.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []m.SchedulerResourceUpdate{{ID: "worker", Limit: 1}, {ID: resourceID, Limit: 1}}}
	var saved m.SchedulerSettings
	var saveErr error
	var save sync.WaitGroup
	save.Add(1)
	go func() {
		defer save.Done()
		saved, saveErr = f.service.UpdateSettings(ctx, actor, update)
	}()
	defer func() {
		cancel()
		admission.Rollback(context.Background())
		save.Wait()
	}()
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		var waiting bool
		if err := f.database.Database().QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE $1::integer=ANY(pg_blocking_pids(pid)))`, admissionPID).Scan(&waiting); err != nil {
			t.Fatal(err)
		}
		if waiting {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal("settings save did not reach the concurrent scheduler transaction")
		case <-ticker.C:
		}
	}
	if err := admission.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	save.Wait()
	if saveErr != nil {
		t.Fatalf("save failed with 256 running jobs and retained history: %v", saveErr)
	}
	if saved.Revision != settings.Revision+1 {
		t.Fatalf("save revision = %d, want %d", saved.Revision, settings.Revision+1)
	}
	for _, resource := range saved.Resources {
		if resource.ID == "worker" || resource.ID == resourceID {
			if resource.Limit != 1 || resource.ActiveJobs != 256 || f.active(resource.ID) != 256 {
				t.Fatalf("lower limit lost running owners: %+v", resource)
			}
		}
	}
	if _, err := f.service.UpdateSettings(t.Context(), actor, update); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale revision accepted during running jobs: %v", err)
	}
	reserve := func() string {
		t.Helper()
		var workflowID string
		if err := pgx.BeginFunc(t.Context(), f.database.Database(), func(tx pgx.Tx) error {
			var err error
			workflowID, err = f.source.ReserveFirst(t.Context(), tx, "document_ai", candidates)
			return err
		}); err != nil {
			t.Fatal(err)
		}
		return workflowID
	}
	if workflowID := reserve(); workflowID != "" {
		t.Fatalf("lowered limit admitted %q before owners drained", workflowID)
	}
	f.exec(`UPDATE document_ai_jobs SET status='cancelled' WHERE status='running'`)
	if workflowID := reserve(); workflowID != "" || f.active("worker") != 256 {
		t.Fatal("visible cancellation released unclosed owners")
	}
	f.exec(`UPDATE document_ai_jobs SET closed_at=clock_timestamp() WHERE status='cancelled' AND document_id<>md5('1')::uuid`)
	if workflowID := reserve(); workflowID != "" || f.active("worker") != 1 {
		t.Fatal("new work admitted while remaining owner equals lowered limit")
	}
	f.exec(`UPDATE document_ai_jobs SET closed_at=clock_timestamp() WHERE status='cancelled' AND closed_at IS NULL`)
	if workflowID := reserve(); workflowID != candidates[0].WorkflowID || f.active("worker") != 1 {
		t.Fatalf("oldest waiting job did not progress after closure: %q", workflowID)
	}
}

func TestSchedulerSettingsSaveDoesNotWaitForRequestCleanup(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	actor := schedulerSettingsActor(t, f)
	running := f.paperless()
	if !f.reserve(running) {
		t.Fatal("initial job was not admitted")
	}
	f.close(running)
	f.exec(`INSERT INTO scheduler_requests(workflow_id,pipeline,state) VALUES('obsolete-ai-waiter','document_ai','waiting')`)
	settings, err := f.service.Settings(t.Context(), actor)
	if err != nil {
		t.Fatal(err)
	}
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err := blocker.Exec(t.Context(), `SELECT workflow_id FROM scheduler_requests FOR UPDATE`); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	saved, err := f.service.UpdateSettings(ctx, actor, m.SchedulerSettingsUpdate{ExpectedRevision: settings.Revision, Resources: []m.SchedulerResourceUpdate{{ID: "worker", Limit: 3}}})
	if err != nil {
		t.Fatalf("limit change waited for unrelated request cleanup: %v", err)
	}
	if saved.Resources[0].Limit != 3 || saved.Resources[0].ActiveJobs != 0 || f.active("worker") != 1 {
		t.Fatalf("save changed stored ownership or counted closed execution: %+v", saved)
	}
}
