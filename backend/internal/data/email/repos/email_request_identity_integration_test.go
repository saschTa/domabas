//go:build integration

package repos

import (
	"errors"
	"sync"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
)

func TestEmailRequestIdentityBindsOwnerNamespaceProviderAndRevision(t *testing.T) {
	pool, _, repository, actor := independentEmailFixture(t)
	first := independentProvider(t, repository, actor)
	second := independentProvider(t, repository, actor)
	input := m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: first.Revision}
	run, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, first.ID, input)
	if err != nil {
		t.Fatal(err)
	}
	if replay, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, first.ID, input); err != nil || replay.ID != run.ID {
		t.Fatalf("identical request lost run: %+v %v", replay, err)
	}
	if _, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, second.ID, input); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("owned cross-provider key: %v", err)
	}
	wrongRevision := input
	wrongRevision.ExpectedRevision++
	if _, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, first.ID, wrongRevision); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("owned revision mismatch: %v", err)
	}
	for _, namespace := range []string{actor.AccountID, ""} {
		foreign := independentEmailActor(t, pool, namespace)
		provider := independentProvider(t, repository, foreign)
		if _, err := independentEmailService(t, pool, repository).Start(t.Context(), foreign, provider.ID, input); !errors.Is(err, m.ErrNotFound) {
			t.Fatalf("foreign request disclosed collision: %v", err)
		}
	}
	var runs, outboxes int
	if err := pool.QueryRow(t.Context(), `SELECT (SELECT count(*) FROM email_runs),(SELECT count(*) FROM email_outbox)`).Scan(&runs, &outboxes); err != nil || runs != 1 || outboxes != 1 {
		t.Fatalf("collision committed work: runs=%d outboxes=%d err=%v", runs, outboxes, err)
	}
}

func TestEmailRequestIdentityConcurrentForeignCollisionHasOneWinner(t *testing.T) {
	pool, _, repository, firstActor := independentEmailFixture(t)
	secondActor := independentEmailActor(t, pool, "")
	actors := []m.EmailActor{firstActor, secondActor}
	providers := []m.EmailProvider{independentProvider(t, repository, firstActor), independentProvider(t, repository, secondActor)}
	input := m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: 1}
	start := make(chan struct{})
	results := make(chan error, 2)
	var workers sync.WaitGroup
	for i := range actors {
		workers.Add(1)
		go func() {
			defer workers.Done()
			<-start
			_, err := independentEmailService(t, pool, repository).Start(t.Context(), actors[i], providers[i].ID, input)
			results <- err
		}()
	}
	close(start)
	workers.Wait()
	close(results)
	winners, hidden := 0, 0
	for err := range results {
		if err == nil {
			winners++
		} else if errors.Is(err, m.ErrNotFound) {
			hidden++
		} else {
			t.Fatalf("unexpected collision outcome: %v", err)
		}
	}
	if winners != 1 || hidden != 1 {
		t.Fatalf("winners=%d hidden=%d", winners, hidden)
	}
}
