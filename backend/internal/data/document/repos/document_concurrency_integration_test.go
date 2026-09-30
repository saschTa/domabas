//go:build integration

package repos_test

import (
	"fmt"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func occupyDocumentCapacity(t *testing.T, f *ingestionFixture, count int) {
	t.Helper()
	for i := range count {
		f.accept(t, f.actor, fmt.Sprintf("%064x", 9000+i), "Retained execution")
		leases, err := f.service.Claim(t.Context(), 1, time.Second, "concurrency-test")
		if err != nil || len(leases) != 1 {
			t.Fatalf("reserve retained capacity: %+v %v", leases, err)
		}
		if err = f.repository.Acknowledge(t.Context(), leases[0], leases[0].WorkflowID, uuid.NewString()); err != nil {
			t.Fatal(err)
		}
	}
}

func TestDocumentConcurrentAdmissionRetainsTenUntilClosure(t *testing.T) {
	f := newIngestionFixture(t)
	for i := range 12 {
		f.accept(t, f.actor, fmt.Sprintf("%064x", 10000+i), "Concurrent original")
	}
	type result struct {
		leases []m.DocumentOutboxLease
		err    error
	}
	results := make(chan result, 20)
	for range cap(results) {
		go func() {
			leases, err := f.service.Claim(t.Context(), 1, time.Second, "concurrent-dispatchers")
			results <- result{leases, err}
		}()
	}
	admitted := map[string]m.DocumentOutboxLease{}
	for range cap(results) {
		got := <-results
		if got.err != nil {
			t.Fatal(got.err)
		}
		for _, lease := range got.leases {
			if _, exists := admitted[lease.Job.DocumentID]; exists {
				t.Fatal("concurrent dispatchers leased the same document")
			}
			admitted[lease.Job.DocumentID] = lease
		}
	}
	if len(admitted) != 10 {
		t.Fatalf("admitted %d documents, want 10", len(admitted))
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing WHERE delivery_deadline IS NULL`); n != 2 {
		t.Fatalf("waiting documents acquired deadlines: %d", n)
	}
	var held m.DocumentOutboxLease
	for _, lease := range admitted {
		held = lease
		break
	}
	if err := f.service.Delete(t.Context(), f.actor, held.Job.DocumentID); err != nil {
		t.Fatal(err)
	}
	if leases, err := f.service.Claim(t.Context(), 1, time.Second, "concurrent-dispatchers"); err != nil || len(leases) != 0 {
		t.Fatalf("deletion released unclosed capacity: %+v %v", leases, err)
	}
	pending := issue12Pending(t, f, held.Job)
	if err := f.service.ResolveExecution(t.Context(), pending, "", "processing_failed", false); err != nil {
		t.Fatal(err)
	}
	if leases, err := f.service.Claim(t.Context(), 1, time.Second, "concurrent-dispatchers"); err != nil || len(leases) != 1 {
		t.Fatalf("verified closure did not free capacity: %+v %v", leases, err)
	}
}
