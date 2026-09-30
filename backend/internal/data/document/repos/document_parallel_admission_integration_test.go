//go:build integration

package repos_test

import (
	"fmt"
	"testing"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestConfiguredDocumentAndAIAdmissionAcrossDispatchers(t *testing.T) {
	for _, ai := range []bool{false, true} {
		t.Run(fmt.Sprint("ai=", ai), func(t *testing.T) {
			f := newIngestionFixture(t)
			limits := r.DocumentIngestionLimits{Concurrency: 12, AIConcurrency: 12, OllamaQueueSize: 24, ConcurrencyMode: "ollama_half_queue", AIConcurrencyMode: "ollama_half_queue", UnlimitedInference: true}
			first := llmSource(t, f, limits)
			second := llmSource(t, f, limits)
			if ai {
				aiIndependentEnableProperties(t, f)
			}
			for i := range 14 {
				doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+7000), "Parallel job")
				if ai {
					aiIndependentReady(t, f, doc, "searchable original")
				}
			}
			type result struct {
				leases []m.DocumentOutboxLease
				err    error
			}
			results := make(chan result, 20)
			for i := range cap(results) {
				go func() {
					source := first
					if i%2 != 0 {
						source = second
					}
					if ai {
						leases, err := source.AIClaim(t.Context(), 1, time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "parallel-ai")
						results <- result{leases, err}
						return
					}
					leases, err := source.ClaimRecords(t.Context(), 1, time.Second, nil, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "parallel-ingestion")
					converted := make([]m.DocumentOutboxLease, len(leases))
					for i, lease := range leases {
						converted[i].ID = lease.ID
					}
					results <- result{converted, err}
				}()
			}
			admitted := map[string]bool{}
			for range cap(results) {
				got := <-results
				if got.err != nil {
					t.Fatal(got.err)
				}
				for _, lease := range got.leases {
					if admitted[lease.ID] {
						t.Fatal("duplicate lease", lease.ID)
					}
					admitted[lease.ID] = true
				}
			}
			if len(admitted) != 12 {
				t.Fatalf("admitted %d, want configured 12", len(admitted))
			}
			query := `SELECT count(*) FROM document_processing WHERE delivery_deadline IS NULL`
			if ai {
				query = `SELECT count(*) FROM document_ai_jobs WHERE admitted_at IS NULL AND delivery_deadline IS NULL`
			}
			if waiting := issue12Count(t, f, query); waiting != 2 {
				t.Fatalf("waiting without deadline: %d", waiting)
			}
			configuration, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
			if err != nil || configuration.Scheduling != nil {
				t.Fatalf("obsolete per-pipeline scheduling remains: %+v %v", configuration.Scheduling, err)
			}
			if count := issue12Count(t, f, `SELECT count(*) FROM scheduler_resources WHERE id IN ('worker','ollama') AND concurrency_limit=12`); count != 2 {
				t.Fatalf("shared resource capacity was not configured: %d", count)
			}
			limits.Concurrency, limits.AIConcurrency = 1, 1
			reduced := llmSource(t, f, limits)
			if ai {
				leases, err := reduced.AIClaim(t.Context(), 1, time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "reduced-ai")
				if err != nil || len(leases) != 0 {
					t.Fatalf("reduction discarded retained AI ownership: %+v %v", leases, err)
				}
			} else {
				leases, err := reduced.ClaimRecords(t.Context(), 1, time.Second, nil, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "reduced-ingestion")
				if err != nil || len(leases) != 0 {
					t.Fatalf("reduction discarded retained ingestion ownership: %+v %v", leases, err)
				}
			}
			after, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
			if err != nil || after.Revision != configuration.Revision || after.Fingerprint != configuration.Fingerprint || after.AutomaticBatchID != configuration.AutomaticBatchID {
				t.Fatalf("runtime capacity changed processing provenance: %+v %v", after, err)
			}
		})
	}
}

func TestResourceDeniedReindexRetriesItsOriginalSchedulerTurn(t *testing.T) {
	f := newIngestionFixture(t)
	f.resourceCapacity(t, 1)
	target := f.accept(t, f.actor, fmt.Sprintf("%064x", 8101), "Reindex target")
	f.ready(t, target, "published reindex target", unitVector(0))
	held := f.accept(t, f.actor, fmt.Sprintf("%064x", 8102), "Occupied model capacity")
	first, err := f.service.Claim(t.Context(), 1, time.Second, "fifo-regression")
	if err != nil || len(first) != 1 || first[0].Job.DocumentID != held.ID {
		t.Fatal(first, err)
	}
	if err = f.repository.Acknowledge(t.Context(), first[0], first[0].WorkflowID, "held-run"); err != nil {
		t.Fatal(err)
	}
	issue12Batch(t, f, f.actor, false)
	ordinary := f.accept(t, f.actor, fmt.Sprintf("%064x", 8103), "Older ordinary outbox")
	blocked, err := f.service.Claim(t.Context(), 1, time.Second, "fifo-regression")
	if err != nil || len(blocked) != 0 {
		t.Fatalf("reindex exceeded occupied resource: %+v %v", blocked, err)
	}
	var enrolled string
	if err = f.connection.QueryRow(t.Context(), `SELECT workflow_id FROM scheduler_requests WHERE state='waiting' ORDER BY sequence LIMIT 1`).Scan(&enrolled); err != nil {
		t.Fatal(err)
	}
	expected := fmt.Sprintf("document-ingestion-v2/%s/%s/2", f.actor.AccountID, target.ID)
	if enrolled != expected {
		t.Fatalf("reindex intent was not enrolled first: %s", enrolled)
	}
	if err = f.repository.Fail(t.Context(), first[0].Job, "processing_failed"); err != nil {
		t.Fatal(err)
	}
	pending := issue12Pending(t, f, first[0].Job)
	if err = f.service.ResolveExecution(t.Context(), pending, pending.RunID, "processing_incomplete", false); err != nil {
		t.Fatal(err)
	}
	resumed, err := f.service.Claim(t.Context(), 1, time.Second, "fifo-regression")
	if err != nil || len(resumed) != 1 || resumed[0].WorkflowID != enrolled {
		t.Fatalf("older ordinary outbox %s displaced an enrolled reindex forever: %+v %v", ordinary.ID, resumed, err)
	}
	var class string
	if err = f.connection.QueryRow(t.Context(), `SELECT last_class FROM document_processing_admission WHERE id`).Scan(&class); err != nil || class != "reindex" {
		t.Fatal("reindex retry lost class rotation", class, err)
	}
}
