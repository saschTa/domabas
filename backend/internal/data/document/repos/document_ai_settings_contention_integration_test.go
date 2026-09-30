//go:build integration

package repos_test

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestDocumentAdmissionYieldsToBusySchedulerAndSettingsSave(t *testing.T) {
	for _, ai := range []bool{false, true} {
		t.Run(fmt.Sprintf("ai=%t", ai), func(t *testing.T) {
			f := newIngestionFixture(t)
			source := llmSource(t, f)
			configuration := aiIndependentEnableProperties(t, f)
			doc := f.accept(t, f.actor, strings.Repeat("f", 64), "Busy scheduler settings")
			if ai {
				aiIndependentReady(t, f, doc, "Published document")
			}
			blocker, err := f.connection.Begin(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			defer blocker.Rollback(context.Background())
			if _, err = blocker.Exec(t.Context(), "SELECT singleton FROM scheduler_settings WHERE singleton FOR UPDATE"); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			policy := m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true})
			if ai {
				leases, err := source.AIClaim(ctx, 1, time.Second, policy, "busy-scheduler")
				if err != nil || len(leases) != 0 {
					t.Fatalf("AI admission must yield to busy scheduler: %+v %v", leases, err)
				}
			} else {
				leases, err := source.ClaimRecords(ctx, 1, time.Second, nil, policy, "busy-scheduler")
				if err != nil || len(leases) != 0 {
					t.Fatalf("ingestion admission must yield to busy scheduler: %+v %v", leases, err)
				}
			}
			configuration, err = f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{
				Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
				LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: true, InvoiceEnabled: new(true), Provider: "ollama", Model: "scheduler-save-model", ContextLength: new(65536)},
			})
			if err != nil || configuration.LLM.Model != "scheduler-save-model" || !configuration.LLM.InvoiceExtractionEnabled() {
				t.Fatalf("settings must save while scheduler remains busy: %+v %v", configuration.LLM, err)
			}
			if err = blocker.Rollback(t.Context()); err != nil {
				t.Fatal(err)
			}
			if ai {
				leases, err := source.AIClaim(t.Context(), 1, time.Second, policy, "busy-scheduler")
				if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != doc.ID {
					t.Fatalf("AI candidate lost after scheduler yield: %+v %v", leases, err)
				}
			} else {
				leases, err := source.ClaimRecords(t.Context(), 1, time.Second, nil, policy, "busy-scheduler")
				if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != doc.ID {
					t.Fatalf("ingestion candidate lost after scheduler yield: %+v %v", leases, err)
				}
			}
		})
	}
}

func TestAISettingsSaveDuringPausedAdmissionTransaction(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	configuration := aiIndependentEnableProperties(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("9", 64), "Paused admission settings")
	aiIndependentReady(t, f, doc, "Published document")
	f.exec(t, `CREATE FUNCTION pause_ai_admission() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':test-ai-admission-pause',0)); RETURN NULL; END $$`)
	f.exec(t, "CREATE TRIGGER pause_ai_admission BEFORE DELETE ON scheduler_requests FOR EACH STATEMENT EXECUTE FUNCTION pause_ai_admission()")
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err = blocker.Exec(t.Context(), `SELECT pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':test-ai-admission-pause',0))`); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	claimed := make(chan error, 1)
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		_, err := source.AIClaim(ctx, 1, time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "paused-admission")
		claimed <- err
	}()
	defer func() {
		cancel()
		<-finished
	}()
	for {
		var paused bool
		if err = f.source.Database().QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity a WHERE a.wait_event_type='Lock' AND $1::integer=ANY(pg_blocking_pids(a.pid)))`, int(f.connection.PgConn().PID())).Scan(&paused); err != nil {
			t.Fatal(err)
		}
		if paused {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
	for _, enabled := range []bool{true, false} {
		saveCtx, saveCancel := context.WithTimeout(t.Context(), time.Second)
		updated, saveErr := f.service.SetProcessingConfiguration(saveCtx, f.actor, m.DocumentProcessingConfiguration{
			Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
			LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: enabled, InvoiceEnabled: new(enabled), Provider: "ollama", Model: "paused-admission-model", ContextLength: new(65536)},
		})
		saveCancel()
		if saveErr != nil || updated.LLM.Enabled != enabled || updated.LLM.InvoiceExtractionEnabled() != enabled || updated.LLM.ContextLength != 65536 {
			t.Fatalf("settings blocked by unrelated admission: %+v %v", updated.LLM, saveErr)
		}
		configuration = updated
	}
	if err = blocker.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err = <-claimed; err != nil {
		t.Fatalf("admission failed after settings changed: %v", err)
	}
}

func TestAISettingsSaveWithLargeSaturatedQueue(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	configuration := aiIndependentEnableProperties(t, f)
	f.resourceCapacity(t, 1)
	doc := f.accept(t, f.actor, strings.Repeat("8", 64), "Saturated queue settings")
	aiIndependentReady(t, f, doc, "Published document")
	aiIndependentClaim(t, source, doc.ID)
	const queued = 50000
	f.exec(t, `INSERT INTO documents(id,account_id,title,created_at) SELECT gen_random_uuid(),$1,'Saturated queue fixture',clock_timestamp() FROM generate_series(1,$2)`, f.actor.AccountID, queued)
	f.exec(t, `INSERT INTO document_processing(document_id,account_id,generation,state,stage,configuration_revision,configuration,updated_at,delivery_deadline,split_pipeline)
 SELECT d.id,d.account_id,1,'ready','complete',p.configuration_revision,p.configuration,clock_timestamp(),clock_timestamp()+interval '1 hour',true FROM documents d CROSS JOIN document_processing p WHERE p.document_id=$1 AND d.id<>$1`, doc.ID)
	f.exec(t, `INSERT INTO scheduler_requests(workflow_id,pipeline) SELECT 'document-ai-v1/'||account_id::text||'/'||document_id::text||'/'||generation::text||'/'||attempt::text,'document_ai' FROM document_ai_jobs WHERE admitted_at IS NULL`)
	f.exec(t, `INSERT INTO scheduler_request_resources(workflow_id,resource_id) SELECT workflow_id,r.id FROM scheduler_requests CROSS JOIN scheduler_resources r WHERE state='waiting' AND r.id IN ('worker','ollama')`)
	for _, table := range []string{"document_ai_jobs", "document_processing", "scheduler_requests", "scheduler_request_resources"} {
		f.exec(t, "ANALYZE "+table)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	started := time.Now()
	leases, err := source.AIClaim(ctx, 1, time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "saturated-queue")
	if err != nil || len(leases) != 0 {
		t.Fatalf("saturated admission exceeded its bounded pass or granted capacity: %+v %v", leases, err)
	}
	t.Logf("admission with %d queued jobs: %s", queued, time.Since(started))
	if count := issue12Count(t, f, "SELECT count(*) FROM scheduler_requests WHERE state='waiting'"); count != queued {
		t.Fatalf("admission lost queued ownership: %d", count)
	}
	configuration, err = f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{
		Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
		LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: false, InvoiceEnabled: new(false), Provider: "ollama", Model: "large-queue-model", ContextLength: new(65536)},
	})
	if err != nil || configuration.LLM.Model != "large-queue-model" || configuration.LLM.Enabled || configuration.LLM.InvoiceExtractionEnabled() {
		t.Fatalf("settings save failed with large queue: %+v %v", configuration.LLM, err)
	}
}

func TestAISettingsRemainEditableWhileMaintenanceCandidateIsBusy(t *testing.T) {
	for _, table := range []string{"documents", "document_ai_jobs"} {
		t.Run(table, func(t *testing.T) {
			f := newIngestionFixture(t)
			source := llmSource(t, f)
			configuration := aiIndependentEnableProperties(t, f)
			doc := f.accept(t, f.actor, strings.Repeat("a", 64), "AI settings contention")
			aiIndependentReady(t, f, doc, "Published text stays searchable")
			lease := aiIndependentClaim(t, source, doc.ID)
			update := m.DocumentProcessingConfiguration{
				Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
				LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: true, InvoiceEnabled: new(false), Provider: "ollama", Model: "replacement-model"},
			}
			configuration, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, update)
			if err != nil {
				t.Fatal(err)
			}
			blocker, err := f.connection.Begin(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			defer blocker.Rollback(context.Background())
			query := "SELECT id FROM documents WHERE id=$1 FOR UPDATE"
			if table == "document_ai_jobs" {
				query = "SELECT id FROM document_ai_jobs WHERE document_id=$1 FOR UPDATE"
			}
			if _, err = blocker.Exec(t.Context(), query, doc.ID); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			if err = f.service.MaintainAI(ctx); err != nil {
				t.Fatalf("busy AI maintenance must yield without blocking settings: %v", err)
			}
			var cursor int64
			var revision *int64
			if err = blocker.QueryRow(t.Context(), "SELECT ai_reschedule_revision,ai_reschedule_cursor FROM document_processing_configuration WHERE id=true").Scan(&revision, &cursor); err != nil {
				t.Fatal(err)
			}
			if revision == nil || *revision != configuration.Revision || cursor != 0 {
				t.Fatalf("busy candidate was skipped permanently: revision=%v cursor=%d", revision, cursor)
			}
			update.ExpectedRevision = &configuration.Revision
			update.LLMUpdate.ContextLength = new(65536)
			update.LLMUpdate.InvoiceEnabled = new(true)
			configuration, err = f.service.SetProcessingConfiguration(ctx, f.actor, update)
			if err != nil {
				t.Fatalf("model/context/invoice update blocked by active AI: %v", err)
			}
			if configuration.LLM.Model != "replacement-model" || configuration.LLM.ContextLength != 65536 || !configuration.LLM.InvoiceExtractionEnabled() {
				t.Fatalf("settings were not retained: %+v", configuration.LLM)
			}
			if err = blocker.Rollback(t.Context()); err != nil {
				t.Fatal(err)
			}
			if err = f.service.MaintainAI(t.Context()); err != nil {
				t.Fatal(err)
			}
			var latestRevision, attempt int64
			if err = f.connection.QueryRow(t.Context(), "SELECT configuration_revision,attempt FROM document_ai_jobs WHERE document_id=$1 ORDER BY attempt DESC LIMIT 1", doc.ID).Scan(&latestRevision, &attempt); err != nil {
				t.Fatal(err)
			}
			if latestRevision != configuration.Revision || attempt != lease.Job.AIAttempt+1 {
				t.Fatalf("deferred candidate missed latest settings: revision=%d attempt=%d", latestRevision, attempt)
			}
			aiIndependentAssertSearchable(t, f, doc.ID)
		})
	}
}

func TestAIClaimSkipsBusyCandidateAndRetriesAfterRelease(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	f.resourceCapacity(t, 2)
	configuration := aiIndependentEnableProperties(t, f)
	first := f.accept(t, f.actor, strings.Repeat("b", 64), "Busy AI claim")
	aiIndependentReady(t, f, first, "First published document")
	second := f.accept(t, f.actor, strings.Repeat("c", 64), "Available AI claim")
	aiIndependentReady(t, f, second, "Second published document")
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err = blocker.Exec(t.Context(), "SELECT id FROM document_ai_jobs WHERE document_id=$1 FOR UPDATE", first.ID); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	policy := m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true})
	leases, err := source.AIClaim(ctx, 1, 30*time.Second, policy, "settings-contention")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != second.ID {
		t.Fatalf("AI claim blocked on busy candidate: %+v %v", leases, err)
	}
	_, err = f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{
		Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
		LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: true, InvoiceEnabled: new(true), Provider: "ollama", Model: "replacement-model", ContextLength: new(65536)},
	})
	if err != nil {
		t.Fatalf("claim contention blocked settings save: %v", err)
	}
	if err = blocker.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	leases, err = source.AIClaim(t.Context(), 1, 30*time.Second, policy, "settings-contention")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != first.ID {
		t.Fatalf("busy candidate was lost after release: %+v %v", leases, err)
	}
}

func TestAIRecoverySkipsBusyLeaseUntilNextPoll(t *testing.T) {
	for _, expired := range []bool{false, true} {
		t.Run(map[bool]string{false: "pending", true: "expired"}[expired], func(t *testing.T) {
			f := newIngestionFixture(t)
			source := llmSource(t, f)
			aiIndependentEnableProperties(t, f)
			doc := f.accept(t, f.actor, strings.Repeat("d", 64), "Busy AI recovery")
			aiIndependentReady(t, f, doc, "Published document")
			lease := aiIndependentClaim(t, source, doc.ID)
			f.exec(t, "UPDATE document_ai_jobs SET next_check_at=clock_timestamp(),delivery_deadline=CASE WHEN $2 THEN clock_timestamp()-interval '1 second' ELSE delivery_deadline END WHERE id=$1", lease.ID, expired)
			blocker, err := f.connection.Begin(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			defer blocker.Rollback(context.Background())
			if _, err = blocker.Exec(t.Context(), "SELECT id FROM document_ai_jobs WHERE id=$1 FOR UPDATE", lease.ID); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			pending, err := source.AIPending(ctx, 100)
			if err != nil || len(pending) != 0 {
				t.Fatalf("recovery blocked on busy AI lease: %+v %v", pending, err)
			}
			if err = blocker.Rollback(t.Context()); err != nil {
				t.Fatal(err)
			}
			pending, err = source.AIPending(t.Context(), 100)
			if err != nil || len(pending) != 1 || pending[0].Job != lease.Job {
				t.Fatalf("recovery lost deferred AI lease: %+v %v", pending, err)
			}
			if expired && pending[0].State != "failed" {
				t.Fatalf("expired lease not failed after release: %+v", pending[0])
			}
		})
	}
}

func TestAIRecoveryResolutionYieldsWithoutLosingExecutionOwnership(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	configuration := aiIndependentEnableProperties(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("e", 64), "Busy AI resolution")
	aiIndependentReady(t, f, doc, "Published document")
	lease := aiIndependentClaim(t, source, doc.ID)
	pending, err := source.AIPending(t.Context(), 100)
	if err != nil || len(pending) != 1 {
		t.Fatalf("AI recovery fixture: %+v %v", pending, err)
	}
	blocker, err := f.connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err = blocker.Exec(t.Context(), "SELECT id FROM document_ai_jobs WHERE id=$1 FOR UPDATE", lease.ID); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	ai := documentAIService(source)
	if err = ai.ResolveExecution(ctx, pending[0], pending[0].RunID, "processing_incomplete", false); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("busy resolution must yield with retryable conflict: %v", err)
	}
	var retained bool
	if err = blocker.QueryRow(t.Context(), "SELECT closed_at IS NULL AND lease_token=$2 AND run_id=$3 FROM document_ai_jobs WHERE id=$1", lease.ID, pending[0].LeaseToken, pending[0].RunID).Scan(&retained); err != nil || !retained {
		t.Fatalf("busy resolution released ownership: %t %v", retained, err)
	}
	_, err = f.service.SetProcessingConfiguration(ctx, f.actor, m.DocumentProcessingConfiguration{
		Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
		LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: true, InvoiceEnabled: new(true), Provider: "ollama", Model: "replacement-model", ContextLength: new(65536)},
	})
	if err != nil {
		t.Fatalf("resolution contention blocked settings save: %v", err)
	}
	if err = blocker.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err = ai.ResolveExecution(t.Context(), pending[0], pending[0].RunID, "processing_incomplete", false); err != nil {
		t.Fatalf("deferred resolution could not reuse retained lease: %v", err)
	}
	if n := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE id=$1 AND closed_at IS NOT NULL AND lease_token IS NULL", lease.ID); n != 1 {
		t.Fatal("deferred resolution did not close its execution")
	}
}
