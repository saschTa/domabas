//go:build integration

package repos

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"testing"
	"time"

	emailsources "github.com/domabas/domabas/backend/internal/data/email/datasources"
	"github.com/domabas/domabas/backend/internal/data/email/datasources/credentials"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func independentEmailActor(t *testing.T, pool *pgxpool.Pool, account string) m.EmailActor {
	t.Helper()
	personal := uuid.NewString()
	if account == "" {
		account = personal
	}
	tx, err := pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	if _, err := tx.Exec(t.Context(), `INSERT INTO accounts(id,name) VALUES($1,'Email test library')`, personal); err != nil {
		t.Fatal(err)
	}
	actor := m.EmailActor{AccountID: account, UserID: uuid.NewString(), CredentialRevision: 1}
	digest := sha256.Sum256([]byte(uuid.NewString()))
	actor.SessionDigest = hex.EncodeToString(digest[:])
	if _, err := tx.Exec(t.Context(), `INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'fixture-hash',$3)`, actor.UserID, actor.UserID+"@example.test", personal); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) VALUES($1,$2,'admin',true,true,'{}')`, personal, actor.UserID); err != nil {
		t.Fatal(err)
	}
	if personal != account {
		if _, err := tx.Exec(t.Context(), `INSERT INTO memberships(account_id,user_id,role,enabled,is_owner,claims) VALUES($1,$2,'admin',true,true,'{}')`, account, actor.UserID); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := tx.Exec(t.Context(), `INSERT INTO sessions(digest,account_id,user_id,credential_revision,expires_at) VALUES($1,$2,$3,1,clock_timestamp()+interval '1 hour')`, actor.SessionDigest, actor.AccountID, actor.UserID); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(t.Context()); err != nil {
		t.Fatal(err)
	}
	return actor
}

func independentEmailFixture(t *testing.T) (*pgxpool.Pool, *emailsources.EmailDataSource, *EmailRepository, m.EmailActor) {
	t.Helper()
	url := testdb.New(t)
	database, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(database.Close)
	if err = database.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	key := make([]byte, 32)
	if _, err = rand.Read(key); err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(map[string]string{"fixture": base64.StdEncoding.EncodeToString(key)})
	if err != nil {
		t.Fatal(err)
	}
	vault, err := credentials.NewEmailCredentialKeyring(string(raw), "fixture")
	if err != nil {
		t.Fatal(err)
	}
	scheduler := schedulersources.NewSchedulerDataSource(database.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	source := emailsources.NewEmailDataSource(database.Database(), scheduler)
	return pool, source, NewEmailRepository(source, vault), independentEmailActor(t, pool, "")
}

func independentProvider(t *testing.T, repository *EmailRepository, actor m.EmailActor) m.EmailProvider {
	t.Helper()
	username, password := "private-login", "fixture-password"
	provider, err := repository.Create(t.Context(), actor, m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders,
		ID: uuid.NewString(), Username: &username, Password: &password,
		EmailSettings: m.EmailSettings{Label: "Private provider", Host: "imap.example.test", Port: 993, Mailbox: "INBOX", Enabled: true, IntervalMinutes: 15, MaxAgeDays: 30, PageSize: 50},
	})
	if err != nil {
		t.Fatal(err)
	}
	return provider
}

func TestIndependentConsentNeedsExplicitRenewalAfterIdentityPasswordReset(t *testing.T) {
	pool, _, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	if _, err := pool.Exec(t.Context(), `UPDATE users SET credential_revision=2 WHERE id=$1`, actor.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE sessions SET credential_revision=2 WHERE digest=$1`, actor.SessionDigest); err != nil {
		t.Fatal(err)
	}
	actor.CredentialRevision = 2
	expected := provider.Revision
	input := m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders, ID: provider.ID, EmailSettings: provider.EmailSettings, ExpectedRevision: &expected}
	unchanged, err := independentEmailService(t, pool, repository).Update(t.Context(), actor, input)
	if err != nil || unchanged.Revision != provider.Revision || unchanged.ConsentState != "renewal_required" {
		t.Fatalf("unchanged enabled save renewed consent: %+v %v", unchanged, err)
	}
	input.Label = "Unrelated label edit"
	changed, err := independentEmailService(t, pool, repository).Update(t.Context(), actor, input)
	if err != nil || changed.Revision != expected+1 || changed.ConsentState != "renewal_required" {
		t.Fatalf("ordinary edit renewed consent: %+v %v", changed, err)
	}
	if _, err = independentEmailService(t, pool, repository).Start(t.Context(), actor, provider.ID, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: changed.Revision}); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("invalid consent allowed manual import: %v", err)
	}
	input.RenewConsent = true
	if _, err = independentEmailService(t, pool, repository).Update(t.Context(), actor, input); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale effective renewal accepted: %v", err)
	}
	expected = changed.Revision
	renewed, err := independentEmailService(t, pool, repository).Update(t.Context(), actor, input)
	if err != nil || renewed.ConsentRevision != 2 || renewed.ConsentState != "valid" || renewed.Revision != expected+1 {
		t.Fatalf("explicit fresh renewal failed: %+v %v", renewed, err)
	}
	noop, err := independentEmailService(t, pool, repository).Update(t.Context(), actor, input)
	if err != nil || noop.Revision != renewed.Revision {
		t.Fatalf("identical stale retry was not a true no-op: %+v %v", noop, err)
	}
}

func TestIndependentProviderOwnershipAndFreshMembership(t *testing.T) {
	pool, _, repository, owner := independentEmailFixture(t)
	provider := independentProvider(t, repository, owner)
	other := independentEmailActor(t, pool, owner.AccountID)
	if _, err := repository.Get(t.Context(), other, provider.ID); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("another namespace owner could inspect private credentials: %v", err)
	}
	page, err := repository.List(t.Context(), other, 20, "")
	if err != nil || len(page.Items) != 0 {
		t.Fatalf("foreign provider listed: %+v %v", page, err)
	}
	if _, err = pool.Exec(t.Context(), `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, owner.AccountID, owner.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err = independentEmailService(t, pool, repository).Get(t.Context(), owner, provider.ID); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("revoked owner could inspect provider: %v", err)
	}
	if _, err = independentEmailService(t, pool, repository).Start(t.Context(), owner, provider.ID, m.EmailStartRun{RequestID: uuid.NewString(), ExpectedRevision: provider.Revision}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("revoked owner could start import: %v", err)
	}
}

func independentAttempt(t *testing.T, source *emailsources.EmailDataSource, repository *EmailRepository, actor m.EmailActor, provider m.EmailProvider) m.EmailAttempt {
	t.Helper()
	run := independentQueuedRun(t, repository, actor, provider)
	execution, err := source.ClaimDelivery(t.Context(), "fixture-email-queue")
	if err != nil || execution == nil {
		t.Fatalf("delivery claim: %+v %v", execution, err)
	}
	if execution.RunID != run.ID {
		t.Fatalf("unexpected run admission %s", execution.RunID)
	}
	workflowRun := uuid.NewString()
	if err = source.AcknowledgeDelivery(t.Context(), *execution, workflowRun); err != nil {
		t.Fatal(err)
	}
	attempt := m.EmailAttempt{ConsentRevision: actor.CredentialRevision, RunID: run.ID, WorkflowID: execution.WorkflowID, WorkflowRunID: workflowRun, TaskQueue: execution.TaskQueue, ActivityID: "page-zero", Token: uuid.NewString(), Number: 1, PageIndex: 0, Deadline: time.Now().Add(time.Minute), ExecutionStartedAt: execution.FirstAttemptAt}
	if _, err = source.ClaimAttempt(t.Context(), attempt, m.EmailPageAdmission()); err != nil {
		t.Fatal(err)
	}
	return attempt
}

func TestIndependentAttemptRetryFencesOldCheckpointAndSurvivesLogout(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	attempt := independentAttempt(t, source, repository, actor, provider)
	if _, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), attempt, m.EmailMailbox{UIDValidity: 7, UIDNext: 101}); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `DELETE FROM sessions WHERE digest=$1`, actor.SessionDigest); err != nil {
		t.Fatal(err)
	}
	newer := attempt
	newer.Number, newer.Token = 2, uuid.NewString()
	if _, err := source.ClaimAttempt(t.Context(), newer, m.EmailPageAdmission()); err != nil {
		t.Fatalf("logout unexpectedly revoked durable consent: %v", err)
	}
	if _, err := source.ClaimAttempt(t.Context(), attempt, m.EmailPageAdmission()); !errors.Is(err, m.ErrStaleAttempt) {
		t.Fatalf("old attempt reclaimed ownership: %v", err)
	}
	if _, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 10, []int64{10}); !errors.Is(err, m.ErrStaleAttempt) {
		t.Fatalf("old attempt advanced cursor: %v", err)
	}
	items, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), newer, false, 10, []int64{10})
	if err != nil || len(items) != 1 {
		t.Fatalf("current discovery failed: %+v %v", items, err)
	}
	var next, count int64
	if err = pool.QueryRow(t.Context(), `SELECT live_next_uid FROM email_mailboxes WHERE provider_id=$1`, provider.ID).Scan(&next); err != nil {
		t.Fatal(err)
	}
	if err = pool.QueryRow(t.Context(), `SELECT messages_discovered FROM email_runs WHERE id=$1`, attempt.RunID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if next != 11 || count != 1 {
		t.Fatalf("stale attempt changed progress: next=%d count=%d", next, count)
	}
	if _, err = pool.Exec(t.Context(), `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, actor.AccountID, actor.UserID); err != nil {
		t.Fatal(err)
	}
	if err = independentPollingService(t, pool, source, repository).SetStage(t.Context(), newer, "importing"); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("revoked authority allowed background mutation: %v", err)
	}
}

func TestIndependentUIDRolloverRetiresPendingWithoutReusingOldSource(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	attempt := independentAttempt(t, source, repository, actor, provider)
	first, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), attempt, m.EmailMailbox{UIDValidity: 7, UIDNext: 3})
	if err != nil {
		t.Fatal(err)
	}
	oldItems, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 2, []int64{1, 2})
	if err != nil || len(oldItems) != 2 {
		t.Fatalf("old discovery: %+v %v", oldItems, err)
	}
	if _, err = pool.Exec(t.Context(), `UPDATE email_messages SET state='accepted',parent_document_id=$2,inspection_state='pending' WHERE id=$1`, oldItems[0].ID, uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	second, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), attempt, m.EmailMailbox{UIDValidity: 8, UIDNext: 3})
	if err != nil || second.MailboxGeneration != first.MailboxGeneration+1 {
		t.Fatalf("rollover: %+v %v", second, err)
	}
	newItems, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 2, []int64{1, 2})
	if err != nil || len(newItems) != 2 || newItems[0].ID == oldItems[0].ID {
		t.Fatalf("new source aliased old UIDs: %+v %v", newItems, err)
	}
	for index, item := range oldItems {
		var state, code, inspection string
		if err = pool.QueryRow(t.Context(), `SELECT state,failure_code,inspection_state FROM email_messages WHERE id=$1`, item.ID).Scan(&state, &code, &inspection); err != nil {
			t.Fatal(err)
		}
		want := "skipped"
		if index == 0 {
			want = "accepted"
		}
		if state != want || code != "mailbox_changed" || inspection != "failed" {
			t.Fatalf("old source not retired safely: state=%s code=%s inspection=%s", state, code, inspection)
		}
	}
}

func TestIndependentAgeWideningRevisitsMoreThanMaintenanceBatchWithoutRewindingLive(t *testing.T) {
	pool, source, repository, actor := independentEmailFixture(t)
	provider := independentProvider(t, repository, actor)
	old := independentAttempt(t, source, repository, actor, provider)
	if _, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), old, m.EmailMailbox{UIDValidity: 7, UIDNext: 201}); err != nil {
		t.Fatal(err)
	}
	for base := int64(0); base < 200; base += 100 {
		uids := make([]int64, 100)
		for index := range uids {
			uids[index] = base + int64(index) + 1
		}
		if _, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), old, false, base+100, uids); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_messages SET state='skipped',failure_code='age_excluded',inspection_state='complete',pending_parts=false,internal_date=clock_timestamp()-interval '60 days' WHERE provider_id=$1`, provider.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE email_messages SET state='accepted',failure_code=NULL,parent_document_id=$2 WHERE provider_id=$1 AND uid=1`, provider.ID, uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	expected := provider.Revision
	settings := provider.EmailSettings
	settings.MaxAgeDays = 90
	updated, err := independentEmailService(t, pool, repository).Update(t.Context(), actor, m.EmailProviderInput{MaximumProviders: m.MaximumEmailProviders, ID: provider.ID, EmailSettings: settings, ExpectedRevision: &expected})
	if err != nil {
		t.Fatal(err)
	}
	if err = independentPollingService(t, pool, source, repository).ResolveExecution(t.Context(), m.EmailExecution{RunID: old.RunID, WorkflowID: old.WorkflowID, TaskQueue: old.TaskQueue}, old.WorkflowRunID, "", false); err != nil {
		t.Fatal(err)
	}
	attempt := independentAttempt(t, source, repository, actor, updated)
	cursor, err := independentPollingService(t, pool, source, repository).SetupMailbox(t.Context(), attempt, m.EmailMailbox{UIDValidity: 7, UIDNext: 202})
	if err != nil || cursor.LiveNext != 201 || cursor.LiveUpper != 201 || cursor.BackfillNext != 1 || cursor.BackfillUpper != 201 {
		t.Fatalf("backfill rewound/delayed live high water: %+v %v", cursor, err)
	}
	for base := int64(0); base < 200; base += 100 {
		uids := make([]int64, 100)
		for index := range uids {
			uids[index] = base + int64(index) + 1
		}
		items, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, true, base+100, uids)
		want := 100
		if base == 0 {
			want = 99
		}
		if err != nil || len(items) != want {
			t.Fatalf("age-widened backfill stranded items beyond the maintenance cap or revived an accepted source: page=%d items=%d want=%d err=%v", base, len(items), want, err)
		}
	}
	live, err := independentPollingService(t, pool, source, repository).DiscoverItems(t.Context(), attempt, false, 201, []int64{201})
	if err != nil || len(live) != 1 || live[0].UID != 201 {
		t.Fatalf("new live mail did not remain discoverable: %+v %v", live, err)
	}
}
