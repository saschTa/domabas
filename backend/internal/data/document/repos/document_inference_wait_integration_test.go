//go:build integration

package repos_test

import (
	"fmt"
	"testing"
	"time"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func TestUnlimitedAdmissionCountsReservationsAndKeepsWaitingJobsDeadlineFree(t *testing.T) {
	f := newIngestionFixture(t, records.DocumentIngestionLimits{Concurrency: 2, UnlimitedInference: true})
	for i := range 6 {
		f.accept(t, f.actor, fmt.Sprintf("%064x", 18000+i), "Queued inference")
	}
	type result struct {
		leases []m.DocumentOutboxLease
		err    error
	}
	results := make(chan result, 12)
	for range cap(results) {
		go func() {
			leases, err := f.service.Claim(t.Context(), 1, time.Second, "inference-capacity")
			results <- result{leases, err}
		}()
	}
	var admitted []m.DocumentOutboxLease
	for range cap(results) {
		got := <-results
		if got.err != nil {
			t.Fatal(got.err)
		}
		admitted = append(admitted, got.leases...)
	}
	if len(admitted) != 2 || !admitted[0].UnlimitedInference || !admitted[1].UnlimitedInference {
		t.Fatalf("concurrent admission exceeded reserved capacity: %+v", admitted)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing WHERE delivery_deadline IS NULL AND processing_started_at IS NULL AND processing_deadline IS NULL`); n != 4 {
		t.Fatalf("waiting jobs acquired execution deadlines: %d", n)
	}
	held := admitted[0]
	if err := f.service.Delete(t.Context(), f.actor, held.Job.DocumentID); err != nil {
		t.Fatal(err)
	}
	if leases, err := f.service.Claim(t.Context(), 1, time.Second, "inference-capacity"); err != nil || len(leases) != 0 {
		t.Fatalf("deleted document released an outstanding reservation: %+v %v", leases, err)
	}
	pending := issue12Pending(t, f, held.Job)
	if !pending.UnlimitedInference {
		t.Fatal("reconciliation lost execution mode")
	}
	if err := f.service.ResolveExecution(t.Context(), pending, "", "processing_cancelled", false); err != nil {
		t.Fatal(err)
	}
	if leases, err := f.service.Claim(t.Context(), 1, time.Second, "inference-capacity"); err != nil || len(leases) != 1 {
		t.Fatalf("confirmed closure did not admit waiting work: %+v %v", leases, err)
	}
}

func TestUnlimitedProcessingSurvivesElapsedDeliveryAndMissingHistory(t *testing.T) {
	f := newIngestionFixture(t, records.DocumentIngestionLimits{Concurrency: 1, UnlimitedInference: true})
	f.accept(t, f.actor, fmt.Sprintf("%064x", 19000), "Slow inference")
	leases, err := f.service.Claim(t.Context(), 1, time.Second, "slow-inference")
	if err != nil || len(leases) != 1 {
		t.Fatalf("admission: %+v %v", leases, err)
	}
	lease := leases[0]
	run := uuid.NewString()
	if err := f.repository.Acknowledge(t.Context(), lease, lease.WorkflowID, run); err != nil {
		t.Fatal(err)
	}
	f.exec(t, `UPDATE document_processing SET delivery_deadline=clock_timestamp()-interval '2 days',processing_started_at=clock_timestamp()-interval '3 days'`)
	f.exec(t, `UPDATE document_processing_executions SET latest_permit_end=clock_timestamp()-interval '3 days',next_check_at=clock_timestamp(),lease_expires_at=NULL`)
	work, err := f.service.Work(t.Context(), lease.Job, "extracting")
	if err != nil {
		t.Fatalf("slow job expired: %v", err)
	}
	if err := f.service.SaveExtraction(t.Context(), lease.Job, work.Revision, "An old request finally completed."); err != nil {
		t.Fatalf("slow extraction could not publish: %v", err)
	}
	pending := issue12Pending(t, f, lease.Job)
	if pending.ProcessingDeadline != nil || !pending.UnlimitedInference {
		t.Fatalf("unlimited work acquired a processing deadline: %+v", pending)
	}
	if err := f.service.ResolveExecution(t.Context(), pending, "", "processing_timeout", true); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_executions WHERE closed_at IS NULL`); n != 1 {
		t.Fatal("missing history released potentially active unlimited execution")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing WHERE state='processing' AND processing_deadline IS NULL`); n != 1 {
		t.Fatal("reconciliation expired unlimited processing")
	}
}
