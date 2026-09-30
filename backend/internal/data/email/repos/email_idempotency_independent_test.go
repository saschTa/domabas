//go:build integration

package repos

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
)

func TestIndependentRequestIdentityPreservesExactReplayAcrossProviderRevision(t *testing.T) {
	pool, _, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	request := m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}
	accepted, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, request)
	if err != nil {
		t.Fatal(err)
	}
	expected := provider.Revision
	settings := provider.EmailSettings
	settings.Label = "Edited after accepted request"
	updated, err := independentEmailService(t, pool, repository).Update(t.Context(), actor, m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders, ID: provider.ID, EmailSettings: settings, ExpectedRevision: &expected})
	if err != nil || updated.Revision == provider.Revision {
		t.Fatalf("provider edit did not advance revision: %v", err)
	}
	replayed, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, request)
	if err != nil || replayed.ID != accepted.ID || replayed.ProviderRevision != request.ExpectedRevision {
		t.Fatalf("exact accepted request lost identity after edit: %+v %v", replayed, err)
	}
	request.ExpectedRevision = updated.Revision
	if _, err = independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, request); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("same request ID accepted a different revision: %v", err)
	}
}

func TestIndependentRequestIdentityIsPrivateAcrossLibrariesForSameOwner(t *testing.T) {
	pool, _, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	request := m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}
	accepted, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, request)
	if err != nil {
		t.Fatal(err)
	}
	other := actor
	other.AccountID = uuid.NewString()
	digest := sha256.Sum256([]byte(uuid.NewString()))
	other.SessionDigest = hex.EncodeToString(digest[:])
	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(t.Context(), `INSERT INTO accounts(id,name) VALUES($1,'Other library')`, other.AccountID); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) VALUES($1,$2,'admin',true,true,'{}')`, other.AccountID, other.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(t.Context(), `INSERT INTO sessions(digest,account_id,user_id,credential_revision,expires_at) VALUES($1,$2,$3,1,clock_timestamp()+interval '1 hour')`, other.SessionDigest, other.AccountID, other.UserID); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	otherProvider := independentProvider(t, repository, other)
	if _, err = independentEmailService(t, pool, repository).Start(t.Context(), other, otherProvider.ID, request); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("same owner could identify a request from another library: %v", err)
	}
	var count int
	if err = pool.QueryRow(t.Context(), `SELECT count(*) FROM email_runs WHERE request_id=$1`, request.RequestID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("cross-library request inserted another durable run: %d %v", count, err)
	}
	replayed, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, request)
	if err != nil || replayed.ID != accepted.ID {
		t.Fatalf("private collision damaged original request: %+v %v", replayed, err)
	}
}

type independentRequestBarrierSource struct {
	EmailSource
	arrived atomic.Int32
	count   int32
	ready   chan struct{}
}

func (s *independentRequestBarrierSource) RequestedRun(ctx context.Context, actor m.EmailActor, provider string, request m.EmailStartRun) (*m.EmailRun, error) {
	run, err := s.EmailSource.RequestedRun(ctx, actor, provider, request)
	if err != nil || run != nil {
		return run, err
	}
	if s.arrived.Add(1) == s.count {
		close(s.ready)
	}
	select {
	case <-s.ready:
		return nil, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func TestIndependentConcurrentExactRequestsCreateOneRunAndOutbox(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	request := m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}
	const count = 8
	barrier := &independentRequestBarrierSource{EmailSource: source, count: count, ready: make(chan struct{})}
	repository = NewEmailRepository(barrier, repository.vault)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	type result struct {
		run m.EmailRun
		err error
	}
	results := make(chan result, count)
	for range count {
		go func() {
			run, err := independentEmailService(t, pool, repository).Start(ctx, actor, provider.ID, request)
			results <- result{run: run, err: err}
		}()
	}
	var id string
	for range count {
		result := <-results
		if result.err != nil || result.run.ID == "" {
			t.Fatalf("concurrent exact request failed: %v", result.err)
		}
		if id == "" {
			id = result.run.ID
		} else if result.run.ID != id {
			t.Fatal("concurrent exact retries returned different durable identities")
		}
	}
	var runs, outbox int
	if err := pool.QueryRow(t.Context(), `SELECT (SELECT count(*) FROM email_runs),(SELECT count(*) FROM email_outbox)`).Scan(&runs, &outbox); err != nil || runs != 1 || outbox != 1 {
		t.Fatalf("concurrent retries created duplicate durable work: runs=%d outbox=%d err=%v", runs, outbox, err)
	}
}

func TestIndependentScheduledNULLRequestIDsAllowRepeatedRuns(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	first := independentProvider(t, repository, actor)
	second := independentProvider(t, repository, actor)
	if _, err := pool.Exec(t.Context(), `UPDATE email_providers SET next_poll_at=clock_timestamp()-interval '1 hour'`); err != nil {
		t.Fatal(err)
	}
	if err := independentSchedule(t, pool, source, repository, "fixture"); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_runs SET status='succeeded',stage='complete',finished_at=clock_timestamp()`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_providers SET next_poll_at=clock_timestamp()-interval '1 hour'`); err != nil {
		t.Fatal(err)
	}
	if err := independentSchedule(t, pool, source, repository, "fixture"); err != nil {
		t.Fatal(err)
	}
	var runs, outbox, nulls, firstRuns, secondRuns int
	err := pool.QueryRow(t.Context(), `SELECT (SELECT count(*) FROM email_runs),(SELECT count(*) FROM email_outbox),(SELECT count(*) FROM email_runs WHERE request_id IS NULL AND trigger='scheduled'),(SELECT count(*) FROM email_runs WHERE provider_id=$1),(SELECT count(*) FROM email_runs WHERE provider_id=$2)`, first.ID, second.ID).Scan(&runs, &outbox, &nulls, &firstRuns, &secondRuns)
	if err != nil || runs != 4 || outbox != 4 || nulls != 4 || firstRuns != 2 || secondRuns != 2 {
		t.Fatalf("global request uniqueness blocked NULL scheduled identities: runs=%d outbox=%d null=%d first=%d second=%d err=%v", runs, outbox, nulls, firstRuns, secondRuns, err)
	}
}
