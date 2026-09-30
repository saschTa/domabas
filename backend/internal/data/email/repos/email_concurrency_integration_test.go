//go:build integration

package repos

import (
	"testing"

	sources "github.com/domabas/domabas/backend/internal/data/email/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func occupyEmailCapacity(t *testing.T, pool *pgxpool.Pool, source *sources.EmailDataSource, repository *EmailRepository, count int) {
	t.Helper()
	actor := independentEmailActor(t, pool, "")
	for range count {
		run := independentQueuedRun(t, repository, actor, independentProvider(t, repository, actor))
		execution, err := source.ClaimDelivery(t.Context(), "concurrency-email")
		if err != nil || execution == nil || execution.RunID != run.ID {
			t.Fatalf("reserve email capacity: %+v %v", execution, err)
		}
		if err = source.AcknowledgeDelivery(t.Context(), *execution, uuid.NewString()); err != nil {
			t.Fatal(err)
		}
	}
}

func TestEmailConcurrentAdmissionRetainsTenUntilClosure(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	for range 12 {
		independentQueuedRun(t, repository, actor, independentProvider(t, repository, actor))
	}
	type result struct {
		execution *m.EmailExecution
		err       error
	}
	results := make(chan result, 8)
	admitted := map[string]m.EmailExecution{}
	for range 12 {
		for range cap(results) {
			go func() {
				execution, err := source.ClaimDelivery(t.Context(), "concurrency-email")
				results <- result{execution, err}
			}()
		}
		for range cap(results) {
			got := <-results
			if got.err != nil {
				t.Fatal(got.err)
			}
			if got.execution != nil {
				if _, exists := admitted[got.execution.RunID]; exists {
					t.Fatal("two dispatchers received the same email start permit")
				}
				admitted[got.execution.RunID] = *got.execution
			}
		}
	}
	if len(admitted) != 10 {
		t.Fatalf("admitted %d email runs, want 10", len(admitted))
	}
	var held m.EmailExecution
	for _, execution := range admitted {
		held = execution
		break
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_runs SET status='cancelled' WHERE id=$1`, held.RunID); err != nil {
		t.Fatal(err)
	}
	if next, err := source.ClaimDelivery(t.Context(), "concurrency-email"); err != nil || next != nil {
		t.Fatalf("logical completion released unclosed capacity: %+v %v", next, err)
	}
	if err := independentPollingService(t, pool, source, repository).ResolveExecution(t.Context(), held, "", "processing_failed", false); err != nil {
		t.Fatal(err)
	}
	if next, err := source.ClaimDelivery(t.Context(), "concurrency-email"); err != nil || next == nil {
		t.Fatalf("verified closure did not free email capacity: %+v %v", next, err)
	}
}
