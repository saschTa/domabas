//go:build integration

package repos

import (
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"testing"
)

func TestEmailSparseUIDCheckpointPersistsAndUIDValidityResets(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	attempt := independentAttempt(t, source, repository, actor, provider)
	first, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), attempt, m.EmailMailbox{UIDValidity: 7, UIDNext: 4000000001})
	if err != nil {
		t.Fatal(err)
	}
	items, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 3000000000, []int64{2000000000, 3000000000})
	if err != nil || len(items) != 2 {
		t.Fatalf("sparse window: %v %v", items, err)
	}
	var next, count int64
	if err = pool.QueryRow(t.Context(), `SELECT live_next_uid FROM email_mailboxes WHERE provider_id=$1`, provider.ID).Scan(&next); err != nil {
		t.Fatal(err)
	}
	if err = pool.QueryRow(t.Context(), `SELECT messages_discovered FROM email_runs WHERE id=$1`, attempt.RunID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if next != 3000000001 || count != 2 {
		t.Fatalf("numeric gap blocked checkpoint: %d %d", next, count)
	}
	if _, err = independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 4000000001, nil); !errors.Is(err, m.ErrStaleAttempt) {
		t.Fatalf("advanced beyond captured upper: %v", err)
	}
	if _, err = independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 4000000000, []int64{2000000000}); !errors.Is(err, m.ErrStaleAttempt) {
		t.Fatalf("accepted UID below cursor: %v", err)
	}
	if _, err = independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 4000000000, nil); err != nil {
		t.Fatalf("empty suffix: %v", err)
	}
	reset, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), attempt, m.EmailMailbox{UIDValidity: 8, UIDNext: 4000000001})
	if err != nil || reset.LiveNext != 1 || reset.MailboxGeneration != first.MailboxGeneration+1 {
		t.Fatalf("UID validity reset: %+v %v", reset, err)
	}
	replacement, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 4000000000, []int64{2000000000})
	if err != nil || len(replacement) != 1 || replacement[0].ID == items[0].ID {
		t.Fatalf("new mailbox reused old source: %+v %v", replacement, err)
	}
}
