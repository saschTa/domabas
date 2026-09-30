//go:build integration

package repos

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/email/datasources/credentials"
	records "github.com/domabas/domabas/backend/internal/data/email/models"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type independentRotatingVault struct {
	p.EmailCredentialVault
	previous p.EmailCredentialVault
}

func (v independentRotatingVault) Open(id m.EmailCredentialIdentity, key string, ciphertext []byte) (m.EmailCredentials, error) {
	if key == v.previous.ActiveID() {
		return v.previous.Open(id, key, ciphertext)
	}
	return v.EmailCredentialVault.Open(id, key, ciphertext)
}
func (v independentRotatingVault) KeyIDs() []string {
	return append(v.EmailCredentialVault.KeyIDs(), v.previous.KeyIDs()...)
}

type independentRotationSource struct {
	EmailSource
	afterSnapshot func()
}

func (s independentRotationSource) RotationCandidates(ctx context.Context, key string, limit int) ([]records.EmailProviderRecord, error) {
	result, err := s.EmailSource.RotationCandidates(ctx, key, limit)
	if err == nil {
		s.afterSnapshot()
	}
	return result, err
}

func TestIndependentRotationPreservesRevisionsAndDoesNotOverwriteOwnerEdit(t *testing.T) {
	pool, source, original, actor := independentEmailFixture(t)
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(map[string]string{"replacement": base64.StdEncoding.EncodeToString(key)})
	if err != nil {
		t.Fatal(err)
	}
	active, err := credentials.NewEmailCredentialKeyring(string(raw), "replacement")
	if err != nil {
		t.Fatal(err)
	}
	vault := independentRotatingVault{EmailCredentialVault: active, previous: original.vault}
	rotating := NewEmailRepository(source, vault)
	provider := independentProvider(t, original, actor)
	before, err := source.Get(t.Context(), actor, provider.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err = rotating.Rotate(t.Context(), 50); err != nil {
		t.Fatal(err)
	}
	after, err := source.Get(t.Context(), actor, provider.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.KeyID != "replacement" || after.Provider.Revision != before.Provider.Revision || after.Provider.SourceGeneration != before.Provider.SourceGeneration || after.Provider.CredentialVersion != before.Provider.CredentialVersion || after.Provider.ConsentRevision != before.Provider.ConsentRevision || !after.Provider.UpdatedAt.Equal(before.Provider.UpdatedAt) {
		t.Fatal("envelope rotation changed provider/source/credential/consent revision or updated timestamp")
	}
	var remaining int
	if err = pool.QueryRow(t.Context(), `SELECT count(*) FROM email_providers WHERE credential_key_id='fixture'`).Scan(&remaining); err != nil || remaining != 0 {
		t.Fatalf("old-key envelope count did not fall to zero: %d %v", remaining, err)
	}
	opened, err := active.Open(emailCredentialIdentityMapper(after), after.KeyID, after.Ciphertext)
	if err != nil || opened.Username != "private-login" || opened.Password != "fixture-password" {
		t.Fatal("rewrapped credentials changed")
	}

	raceProvider := independentProvider(t, original, actor)
	newPassword := "owner-replaced-password"
	var edited m.EmailProvider
	raceSource := independentRotationSource{EmailSource: source, afterSnapshot: func() {
		expected := raceProvider.Revision
		edited, err = independentEmailService(t, pool, rotating).Update(t.Context(), actor, m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders, ID: raceProvider.ID, EmailSettings: raceProvider.EmailSettings, ExpectedRevision: &expected, Password: &newPassword})
		if err != nil {
			t.Fatal(err)
		}
	}}
	if err = NewEmailRepository(raceSource, vault).Rotate(t.Context(), 50); err != nil {
		t.Fatal(err)
	}
	latest, err := source.Get(t.Context(), actor, raceProvider.ID)
	if err != nil {
		t.Fatal(err)
	}
	opened, err = active.Open(emailCredentialIdentityMapper(latest), latest.KeyID, latest.Ciphertext)
	if err != nil || opened.Password != newPassword || latest.Provider.CredentialVersion != raceProvider.CredentialVersion+1 || latest.Provider.Revision != edited.Revision || latest.Provider.SourceGeneration != raceProvider.SourceGeneration || latest.Provider.ConsentRevision != raceProvider.ConsentRevision {
		t.Fatal("stale rotation snapshot overwrote owner edit or changed unrelated revisions")
	}
}

func independentQueuedRun(t *testing.T, repository *EmailRepository, actor m.EmailActor, provider m.EmailProvider) m.EmailRun {
	t.Helper()
	facts, err := repository.UpdateFacts(t.Context(), actor, provider.ID)
	if err != nil {
		t.Fatal(err)
	}
	command, err := m.PlanEmailStart(facts, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}, actor.CredentialRevision)
	if err != nil {
		t.Fatal(err)
	}
	run, err := repository.Start(t.Context(), actor, provider.ID, command)
	if err != nil {
		t.Fatal(err)
	}
	return run
}

func independentAdmission(t *testing.T, pool *pgxpool.Pool, runs ...string) *string {
	t.Helper()
	var id *string
	run := ""
	if len(runs) > 0 {
		run = runs[0]
	}
	if err := pool.QueryRow(t.Context(), `SELECT (SELECT run_id::text FROM email_executions WHERE closed_at IS NULL AND ($1='' OR run_id::text=$1) ORDER BY first_attempt_at,run_id LIMIT 1)`, run).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func TestIndependentRevokedOldestDeliveryRetiresAndPreservesOpenExecutionAdmission(t *testing.T) {
	for _, admitted := range []bool{false, true} {
		t.Run(map[bool]string{false: "queued", true: "open_execution"}[admitted], func(t *testing.T) {
			pool, source, repository, actor := independentEmailFixture(t)
			if admitted {
				occupyEmailCapacity(t, pool, source, repository, m.MaxConcurrentRuns-1)
			}
			first := independentQueuedRun(t, repository, actor, independentProvider(t, repository, actor))
			if _, err := pool.Exec(t.Context(), `UPDATE email_outbox SET available_at=clock_timestamp()-interval '1 hour' WHERE run_id=$1`, first.ID); err != nil {
				t.Fatal(err)
			}
			other := independentEmailActor(t, pool, "")
			second := independentQueuedRun(t, repository, other, independentProvider(t, repository, other))
			if admitted {
				execution, err := independentPollingService(t, pool, source, repository).ClaimDelivery(t.Context(), "independent-queue")
				if err != nil || execution == nil || execution.RunID != first.ID {
					t.Fatalf("first admission failed: %+v %v", execution, err)
				}
				if _, err = pool.Exec(t.Context(), `UPDATE email_outbox SET available_at=clock_timestamp()-interval '1 hour',lease_expires_at=clock_timestamp()-interval '1 second' WHERE run_id=$1`, first.ID); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := pool.Exec(t.Context(), `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, actor.AccountID, actor.UserID); err != nil {
				t.Fatal(err)
			}
			if execution, err := independentPollingService(t, pool, source, repository).ClaimDelivery(t.Context(), "independent-queue"); err != nil || execution != nil {
				t.Fatalf("revoked run admitted: %+v %v", execution, err)
			}
			var status string
			var acknowledged bool
			if err := pool.QueryRow(t.Context(), `SELECT r.status,o.acknowledged_at IS NOT NULL FROM email_runs r JOIN email_outbox o ON o.run_id=r.id WHERE r.id=$1`, first.ID).Scan(&status, &acknowledged); err != nil || status != "cancelled" || !acknowledged {
				t.Fatalf("revoked oldest remains eligible: %s %v %v", status, acknowledged, err)
			}
			execution, err := independentPollingService(t, pool, source, repository).ClaimDelivery(t.Context(), "independent-queue")
			if err != nil {
				t.Fatal(err)
			}
			if admitted {
				if execution != nil {
					t.Fatal("new provider admitted before old execution closure")
				}
				slot := independentAdmission(t, pool, first.ID)
				if slot == nil || *slot != first.ID {
					t.Fatal("revocation prematurely freed persisted execution admission")
				}
				var fenced, closed bool
				if err := pool.QueryRow(t.Context(), `SELECT terminal_fenced_at IS NOT NULL,closed_at IS NOT NULL FROM email_executions WHERE run_id=$1`, first.ID).Scan(&fenced, &closed); err != nil || !fenced || closed {
					t.Fatalf("revoked execution not safely fenced: %v %v %v", fenced, closed, err)
				}
			} else if execution == nil || execution.RunID != second.ID {
				t.Fatalf("retired oldest starved valid provider: %+v", execution)
			}
		})
	}
}

func TestIndependentMissingHistoryKeepsAdmissionUntilSafeHorizonAndFencesLateStarts(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	first := independentQueuedRun(t, repository, actor, independentProvider(t, repository, actor))
	if _, err := pool.Exec(t.Context(), `UPDATE email_outbox SET available_at=clock_timestamp()-interval '1 hour' WHERE run_id=$1`, first.ID); err != nil {
		t.Fatal(err)
	}
	second := independentQueuedRun(t, repository, actor, independentProvider(t, repository, actor))
	execution, err := independentPollingService(t, pool, source, repository).ClaimDelivery(t.Context(), "independent-queue")
	if err != nil || execution == nil || execution.RunID != first.ID {
		t.Fatalf("first admission failed: %+v %v", execution, err)
	}
	if err = independentPollingService(t, pool, source, repository).ResolveExecution(t.Context(), *execution, "", "", true); err != nil {
		t.Fatal(err)
	}
	if slot := independentAdmission(t, pool); slot == nil || *slot != first.ID {
		t.Fatal("fresh NotFound freed possibly live execution")
	}
	if _, err = pool.Exec(t.Context(), `UPDATE email_executions SET first_attempt_at=statement_timestamp()-interval '24 hours 4 minutes',start_window_end=statement_timestamp()-interval '5 minutes',latest_permit_end=statement_timestamp()-interval '10 minutes' WHERE run_id=$1`, first.ID); err != nil {
		t.Fatal(err)
	}
	if _, err = pool.Exec(t.Context(), `UPDATE email_outbox SET available_at=clock_timestamp()-interval '1 hour',lease_expires_at=clock_timestamp()-interval '1 minute' WHERE run_id=$1`, first.ID); err != nil {
		t.Fatal(err)
	}
	var permit time.Time
	if err = pool.QueryRow(t.Context(), `SELECT latest_permit_end FROM email_executions WHERE run_id=$1`, first.ID).Scan(&permit); err != nil {
		t.Fatal(err)
	}
	if late, err := independentPollingService(t, pool, source, repository).ClaimDelivery(t.Context(), "independent-queue"); err != nil || late != nil {
		t.Fatalf("expired start window issued new permit: %+v %v", late, err)
	}
	var unchanged time.Time
	if err = pool.QueryRow(t.Context(), `SELECT latest_permit_end FROM email_executions WHERE run_id=$1`, first.ID).Scan(&unchanged); err != nil || !unchanged.Equal(permit) {
		t.Fatalf("expired permit moved: %v", err)
	}
	if err = independentPollingService(t, pool, source, repository).ResolveExecution(t.Context(), *execution, "", "", true); err != nil {
		t.Fatal(err)
	}
	if slot := independentAdmission(t, pool); slot == nil || *slot != first.ID {
		t.Fatal("10-minute absence released 11-minute safety horizon")
	}
	if _, err = pool.Exec(t.Context(), `UPDATE email_executions SET latest_permit_end=clock_timestamp()-interval '12 minutes' WHERE run_id=$1`, first.ID); err != nil {
		t.Fatal(err)
	}
	if err = independentPollingService(t, pool, source, repository).ResolveExecution(t.Context(), *execution, "", "", true); err != nil {
		t.Fatal(err)
	}
	if slot := independentAdmission(t, pool); slot != nil {
		t.Fatal("safe absent execution did not free admission")
	}
	var status, code string
	var closed bool
	if err = pool.QueryRow(t.Context(), `SELECT r.status,r.failure_code,e.closed_at IS NOT NULL FROM email_runs r JOIN email_executions e ON e.run_id=r.id WHERE r.id=$1`, first.ID).Scan(&status, &code, &closed); err != nil || status != "failed" || code != "processing_incomplete" || !closed {
		t.Fatalf("absent execution not durably settled: %s %s %v %v", status, code, closed, err)
	}
	next, err := independentPollingService(t, pool, source, repository).ClaimDelivery(t.Context(), "independent-queue")
	if err != nil || next == nil || next.RunID != second.ID {
		t.Fatalf("safe closure did not admit next provider: %+v %v", next, err)
	}
}

func TestIndependentMissingKeysPauseSchedulingDeliveryButPermitManualReplay(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	request := m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}
	run, err := independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, request)
	if err != nil {
		t.Fatal(err)
	}
	other := independentProvider(t, repository, actor)
	if _, err = pool.Exec(t.Context(), `UPDATE email_providers SET next_poll_at=clock_timestamp()-interval '1 hour' WHERE id=$1`, other.ID); err != nil {
		t.Fatal(err)
	}
	if err = independentSchedule(t, pool, source, repository, "not-the-saved-key"); err != nil {
		t.Fatal(err)
	}
	var count int
	if err = pool.QueryRow(t.Context(), `SELECT count(*) FROM email_runs`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("missing key created automatic run: %d %v", count, err)
	}
	if delivery, err := source.ClaimDelivery(t.Context(), "independent-queue", "not-the-saved-key"); err != nil || delivery != nil {
		t.Fatalf("missing key claimed delivery: %+v %v", delivery, err)
	}
	if slot := independentAdmission(t, pool); slot != nil {
		t.Fatal("missing key occupied admission")
	}
	absent, err := credentials.NewEmailCredentialKeyring("", "")
	if err != nil {
		t.Fatal(err)
	}
	withoutKeys := NewEmailRepository(source, absent)
	replayed, err := independentEmailService(t, pool, withoutKeys).Start(t.Context(), actor, provider.ID, request)
	if err != nil || replayed.ID != run.ID {
		t.Fatalf("lost key broke accepted request replay: %+v %v", replayed, err)
	}
	if _, err = independentEmailService(t, pool, withoutKeys).Start(t.Context(), actor, other.ID, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: other.Revision}); !errors.Is(err, m.ErrUnavailable) {
		t.Fatalf("missing keys allowed new request: %v", err)
	}
	if err = independentSchedule(t, pool, source, repository, "fixture"); err != nil {
		t.Fatal(err)
	}
	if err = pool.QueryRow(t.Context(), `SELECT count(*) FROM email_runs`).Scan(&count); err != nil || count != 2 {
		t.Fatalf("restored key did not resume scheduling: %d %v", count, err)
	}
	if delivery, err := source.ClaimDelivery(t.Context(), "independent-queue", "fixture"); err != nil || delivery == nil {
		t.Fatalf("restored key did not resume delivery: %+v %v", delivery, err)
	}
}
