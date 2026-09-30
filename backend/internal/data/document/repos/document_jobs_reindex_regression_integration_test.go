//go:build integration

package repos_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	"github.com/google/uuid"
)

func issue12Maintenance(t *testing.T, f *ingestionFixture) *sources.DocumentDataSource {
	t.Helper()
	return sources.NewDocumentIngestionDataSource(f.source.Database(), fixturePublication{}, f.scheduler)
}
func issue12Count(t *testing.T, f *ingestionFixture, query string, args ...any) int64 {
	t.Helper()
	var count int64
	if err := f.connection.QueryRow(t.Context(), query, args...).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
}
func issue12Batch(t *testing.T, f *ingestionFixture, actor m.DocumentActor, system bool) m.DocumentReindexBatch {
	t.Helper()
	c, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
	if err != nil {
		t.Fatal(err)
	}
	batch, err := f.service.CreateBatch(t.Context(), actor, system, m.DocumentReindexRequest{RequestID: uuid.NewString(), ConfigurationRevision: c.Revision})
	if err != nil {
		t.Fatal(err)
	}
	return batch
}
func issue12Maintain(t *testing.T, f *ingestionFixture, passes int) {
	t.Helper()
	for range passes {
		if err := f.service.MaintainProcessing(t.Context()); err != nil {
			t.Fatal(err)
		}
	}
}
func issue12Pending(t *testing.T, f *ingestionFixture, job m.DocumentJob) m.DocumentPendingJob {
	t.Helper()
	f.exec(t, `UPDATE document_processing_executions SET next_check_at=clock_timestamp(),lease_expires_at=NULL WHERE account_id=$1 AND document_id=$2 AND generation=$3`, job.AccountID, job.DocumentID, job.Generation)
	pending, err := f.repository.Pending(t.Context(), 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range pending {
		if p.Job == job {
			return p
		}
	}
	t.Fatalf("execution reservation missing for %v", job)
	return m.DocumentPendingJob{}
}
func issue12Grant(t *testing.T, f *ingestionFixture, a m.DocumentActor, claims []string) {
	t.Helper()
	f.exec(t, `UPDATE memberships SET is_owner=false,role='viewer',claims=$3 WHERE account_id=$1 AND user_id=$2`, a.AccountID, a.UserID, claims)
}

func TestIssue12SettingsNoopPreconditionAndABAHistory(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	a := f.actor
	original, err := f.service.GetProcessingConfiguration(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	changed := original
	changed.Language = "eng"
	changed.ExpectedRevision = &original.Revision
	second, err := f.service.SetProcessingConfiguration(ctx, a, changed)
	if err != nil {
		t.Fatal(err)
	}
	if second.Revision != original.Revision+1 || second.Fingerprint == original.Fingerprint || second.AutomaticBatchID == "" {
		t.Fatalf("real change did not atomically adopt identity and batch: %+v", second)
	}
	stale := original.Revision
	changed.ExpectedRevision = &stale
	noop, err := f.service.SetProcessingConfiguration(ctx, a, changed)
	if err != nil || noop.Revision != second.Revision || noop.AutomaticBatchID != second.AutomaticBatchID {
		t.Fatalf("stale identical save was not a no-op: %+v %v", noop, err)
	}
	staleChange := original
	staleChange.ExpectedRevision = &stale
	if _, err = f.service.SetProcessingConfiguration(ctx, a, staleChange); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale real change accepted: %v", err)
	}
	staleChange.ExpectedRevision = &second.Revision
	third, err := f.service.SetProcessingConfiguration(ctx, a, staleChange)
	if err != nil {
		t.Fatal(err)
	}
	if third.Revision != second.Revision+1 || third.Fingerprint != original.Fingerprint || third.AutomaticBatchID == second.AutomaticBatchID {
		t.Fatalf("A-B-A lost a durable event: %+v", third)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_configurations`); n != 3 {
		t.Fatalf("immutable history count=%d", n)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches WHERE reason='configuration_change'`); n != 2 {
		t.Fatalf("no-op created or change lost automatic batch: %d", n)
	}
	previous, err := f.service.Batch(ctx, a, true, second.AutomaticBatchID)
	if err != nil || previous.Status != "superseded" {
		t.Fatalf("old batch not superseded: %+v %v", previous, err)
	}
}

func TestIssue12MetadataOnlyBatchTerminatesAndExcludesLaterAcceptance(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	for i := 0; i < 105; i++ {
		if _, err := f.documents.Create(ctx, f.actor.AccountID, m.Document{ID: uuid.NewString(), Title: fmt.Sprintf("Metadata %d", i), CreatedAt: time.Now().UTC()}); err != nil {
			t.Fatal(err)
		}
	}
	staged := f.stage(t, f.actor, strings.Repeat("6", 64))
	batch := issue12Batch(t, f, f.actor, false)
	metadata, err := (m.DocumentMetadata{Title: "Upload staged before cutoff, accepted afterward"}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	uploaded, err := f.acceptReservation(ctx, f.actor, staged.ID, metadata, time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	late, err := f.documents.Create(ctx, f.actor.AccountID, m.Document{ID: uuid.NewString(), Title: "After cutoff", CreatedAt: time.Now().Add(-time.Hour)})
	if err != nil {
		t.Fatal(err)
	}
	issue12Maintain(t, f, 4)
	got, err := f.service.Batch(ctx, f.actor, false, batch.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != "succeeded" || !got.EnumerationComplete || got.Discovered != 105 || got.Skipped != 105 || got.Waiting != 0 || got.Running != 0 || got.FinishedAt == nil {
		t.Fatalf("all-skipped batch did not finish with exact counters: %+v", got)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_items WHERE batch_id=$1 AND document_id=$2`, batch.ID, late.ID); n != 0 {
		t.Fatal("backdated post-cutoff document entered batch")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_items WHERE batch_id=$1 AND document_id=$2`, batch.ID, uploaded.ID); n != 0 {
		t.Fatal("staged but unaccepted upload entered an earlier cutoff")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_executions`); n != 0 {
		t.Fatal("metadata-only skips occupied execution capacity")
	}
}

func TestIssue12BatchRequestIdentityScopeAndLostResponseRetry(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	other := f.addActor(t)
	batch := issue12Batch(t, f, f.actor, false)
	request := m.DocumentReindexRequest{RequestID: batch.ID, ConfigurationRevision: batch.ConfigurationRevision}
	if _, err := f.service.CreateBatch(ctx, other, false, request); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign namespace UUID collision exposed owned details: %v", err)
	}
	if _, err := f.service.CreateBatch(ctx, f.actor, true, request); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("namespace UUID was accepted as system request: %v", err)
	}
	current, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil {
		t.Fatal(err)
	}
	current.Language = "eng"
	if _, err = f.service.SetProcessingConfiguration(ctx, f.actor, current); err != nil {
		t.Fatal(err)
	}
	same, err := f.service.CreateBatch(ctx, f.actor, false, request)
	if err != nil || same.ID != batch.ID || same.Status != "superseded" {
		t.Fatalf("authorized lost-response retry lost accepted old revision: %+v %v", same, err)
	}
	request.ConfigurationRevision++
	if _, err = f.service.CreateBatch(ctx, f.actor, false, request); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("owned request payload change not rejected: %v", err)
	}
	issue12Grant(t, f, f.actor, []string{"documents:jobs:read"})
	if _, err = f.service.CreateBatch(ctx, f.actor, false, m.DocumentReindexRequest{RequestID: batch.ID, ConfigurationRevision: batch.ConfigurationRevision}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("revoked reindex authority recovered request before guard: %v", err)
	}
}

func TestIssue12JobTitleClaimsCursorBindingAndDeletionHistory(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	a := f.actor
	first := f.accept(t, a, strings.Repeat("a", 64), "First sensitive title")
	second := f.accept(t, a, strings.Repeat("b", 64), "Second sensitive title")
	page, err := f.service.Jobs(ctx, a, m.DocumentProcessingPageInput{Limit: 1})
	if err != nil || len(page.Items) != 1 || page.NextCursor == "" || page.Items[0].DocumentTitle == nil {
		t.Fatalf("initial history page: %+v %v", page, err)
	}
	for _, input := range []m.DocumentProcessingPageInput{{Limit: 2, Cursor: page.NextCursor}, {Limit: 1, Cursor: page.NextCursor, Status: "queued"}, {Limit: 1, Cursor: page.NextCursor, DocumentID: first.ID}} {
		if _, err = f.service.Jobs(ctx, a, input); !issue12Validation(err) {
			t.Fatalf("cursor reused with changed criteria: %+v %v", input, err)
		}
	}
	other := f.addActor(t)
	if _, err = f.service.Jobs(ctx, other, m.DocumentProcessingPageInput{Limit: 1, Cursor: page.NextCursor}); !issue12Validation(err) {
		t.Fatalf("foreign namespace accepted cursor: %v", err)
	}
	if _, err = f.service.Batches(ctx, a, false, m.DocumentProcessingPageInput{Limit: 1, Cursor: page.NextCursor}); !issue12Validation(err) {
		t.Fatalf("cross-operation cursor accepted: %v", err)
	}
	issue12Grant(t, f, a, []string{"documents:jobs:read"})
	restricted := services.NewDocumentIngestionService(f.repository, nil, nil, documentDeniedAuthority{authority: f.authority, claim: "documents:read"}, time.Now)
	hidden, err := restricted.Jobs(ctx, a, m.DocumentProcessingPageInput{Limit: 10})
	if err != nil {
		t.Fatal(err)
	}
	for _, job := range hidden.Items {
		if job.DocumentTitle != nil {
			t.Fatal("job-only privilege leaked live title")
		}
	}
	issue12Grant(t, f, a, []string{"documents:jobs:read", "documents:read", "documents:delete"})
	if err = f.service.Delete(ctx, a, second.ID); err != nil {
		t.Fatal(err)
	}
	deleted, err := f.service.Jobs(ctx, a, m.DocumentProcessingPageInput{Limit: 10, DocumentID: second.ID})
	if err != nil || len(deleted.Items) != 1 || deleted.Items[0].Status != "cancelled" || deleted.Items[0].DocumentTitle != nil || !deleted.Items[0].DocumentDeleted {
		t.Fatalf("deletion lost/smeared history: %+v %v", deleted, err)
	}
	issue12Grant(t, f, a, []string{})
	if _, err = f.service.Jobs(ctx, a, m.DocumentProcessingPageInput{Limit: 1, Cursor: page.NextCursor}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("cursor bypassed claim revocation: %v", err)
	}
}

func TestIssue12AdmissionSurvivesDeletedUnknownExecutionAndMissingHorizon(t *testing.T) {
	f := newIngestionFixture(t)
	occupyDocumentCapacity(t, f, m.MaxConcurrentProcessing-1)
	ctx := t.Context()
	a := f.actor
	first := f.accept(t, a, strings.Repeat("c", 64), "Admitted")
	second := f.accept(t, a, strings.Repeat("d", 64), "Waiting")
	leases, err := f.service.Claim(ctx, 1, 30*time.Second, "issue12-disposable")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != first.ID {
		t.Fatalf("initial claim: %+v %v", leases, err)
	}
	lease := leases[0]
	if _, err = f.service.Work(ctx, m.DocumentJob{AccountID: a.AccountID, DocumentID: second.ID, Generation: 1}, "extracting"); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("waiting activity executed without admission: %v", err)
	}
	f.exec(t, `UPDATE document_outbox SET available_at=clock_timestamp()-interval '2 days' WHERE document_id=$1`, second.ID)
	if err = f.service.Delete(ctx, a, first.ID); err != nil {
		t.Fatal(err)
	}
	if got, err := f.service.Claim(ctx, 1, 30*time.Second, "issue12-disposable"); err != nil || len(got) != 0 {
		t.Fatalf("deletion freed unresolved execution reservation: %+v %v", got, err)
	}
	pending := issue12Pending(t, f, lease.Job)
	if err = f.service.ResolveExecution(ctx, pending, "", "processing_timeout", true); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_executions WHERE closed_at IS NULL`); n != m.MaxConcurrentProcessing {
		t.Fatal("early NotFound released potentially running execution")
	}
	f.exec(t, `UPDATE document_processing_executions SET latest_permit_end=clock_timestamp()-interval '16 minutes',start_retry_until=clock_timestamp()-interval '1 second' WHERE document_id=$1`, first.ID)
	pending = issue12Pending(t, f, lease.Job)
	if err = f.service.ResolveExecution(ctx, pending, "", "processing_timeout", true); err != nil {
		t.Fatal(err)
	}
	next, err := f.service.Claim(ctx, 1, 30*time.Second, "issue12-disposable")
	if err != nil || len(next) != 1 || next[0].Job.DocumentID != second.ID {
		t.Fatalf("reachable post-horizon NotFound did not free slot: %+v %v", next, err)
	}
	if err = f.repository.Acknowledge(ctx, lease, lease.WorkflowID, uuid.NewString()); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("late old holder resurrected closed execution: %v", err)
	}
	history, err := f.service.Jobs(ctx, a, m.DocumentProcessingPageInput{DocumentID: first.ID})
	if err != nil || history.Items[0].Status != "cancelled" {
		t.Fatalf("recovery rewrote deleted terminal outcome: %+v %v", history, err)
	}
	var remainingSeconds int64
	if err = f.connection.QueryRow(ctx, `SELECT extract(epoch FROM delivery_deadline-clock_timestamp())::bigint FROM document_processing WHERE document_id=$1`, second.ID).Scan(&remainingSeconds); err != nil {
		t.Fatal(err)
	}
	if remainingSeconds < 23*60*60 {
		t.Fatal("waiting upload inherited old delivery deadline")
	}
}

func TestIssue12InstalledManifestDriftAndUnchangedFailedAdoption(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	source := issue12Maintenance(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("e", 64), "Unchanged failure")
	job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	f.admit(t, job)
	if err := f.repository.Fail(ctx, job, "processing_failed"); err != nil {
		t.Fatal(err)
	}
	f.exec(t, `UPDATE document_processing_configuration SET adopted=false`)
	if err := initializeDocumentSource(ctx, source); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches`); n != 0 {
		t.Fatal("unchanged failed snapshot was automatically retried as adoption")
	}
	current, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil {
		t.Fatal(err)
	}
	old := current
	old.ExtractionRevision = "older-extraction"
	old.Fingerprint, err = old.CanonicalFingerprint()
	if err != nil {
		t.Fatal(err)
	}
	body, err := json.Marshal(old)
	if err != nil {
		t.Fatal(err)
	}
	f.exec(t, `UPDATE document_processing_configuration SET configuration=$1,fingerprint=$2,manifest_revision=0,manifest_fingerprint=NULL`, body, old.Fingerprint)
	if err = initializeDocumentSource(ctx, source); err != nil {
		t.Fatal(err)
	}
	adopted, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil || adopted.Revision != current.Revision+1 || adopted.AutomaticBatchID == "" {
		t.Fatalf("installed drift did not atomically advance revision and schedule: %+v %v", adopted, err)
	}
	if err = initializeDocumentSource(ctx, source); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches WHERE configuration_revision=$1`, adopted.Revision); n != 1 {
		t.Fatalf("repeated startup duplicated automatic work: %d", n)
	}
	f.exec(t, `UPDATE document_processing_configuration SET manifest_revision=manifest_revision+1`)
	if err = source.ProcessingReady(ctx); !errors.Is(err, m.ErrUnavailable) {
		t.Fatalf("older installed manifest passed readiness: %v", err)
	}
	if _, err = f.service.Claim(ctx, 1, time.Second, "issue12"); !errors.Is(err, m.ErrUnavailable) {
		t.Fatalf("older installed binary admitted work: %v", err)
	}
}

func issue12Validation(err error) bool {
	var validation m.DocumentValidationError
	return errors.As(err, &validation)
}

type issue12JobOnlyPolicy struct{}

func (issue12JobOnlyPolicy) AllowsAuthority(_ string, _ bool, _ []string, _ string, permission string) bool {
	return permission == "documents:jobs:read"
}

func TestIssue12LockedPrefixMakesProgressWithoutIdentityLockInversion(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	for i := 0; i < 21; i++ {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+1), fmt.Sprintf("Failed original %d", i))
		if err := f.repository.Fail(ctx, m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}, "processing_failed"); err != nil {
			t.Fatal(err)
		}
	}
	batch := issue12Batch(t, f, f.actor, false)
	issue12Maintain(t, f, 2)
	f.exec(t, `UPDATE document_reindex_items SET next_check_at='2000-01-01' WHERE batch_id=$1`, batch.ID)
	lock, err := f.source.Database().Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Rollback(context.Background())
	if _, err = lock.Exec(ctx, `SELECT id FROM accounts WHERE id=$1 FOR UPDATE`, f.actor.AccountID); err != nil {
		t.Fatal(err)
	}
	rows, err := lock.Query(ctx, `SELECT id FROM documents WHERE account_id=$1 ORDER BY id LIMIT 20 FOR UPDATE`, f.actor.AccountID)
	if err != nil {
		t.Fatal(err)
	}
	locked := map[string]bool{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		locked[id] = true
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		t.Fatal(err)
	}
	bounded, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	first, err := f.service.Claim(bounded, 1, time.Second, "issue12-fairness")
	if err != nil || len(first) != 0 {
		t.Fatalf("locked prefix should defer rather than block/drop intents: %+v %v", first, err)
	}
	second, err := f.service.Claim(bounded, 1, time.Second, "issue12-fairness")
	if err != nil || len(second) != 1 || locked[second[0].Job.DocumentID] {
		t.Fatalf("scheduler starved unlocked item beyond fixed prefix or needed locked identity row: %+v %v", second, err)
	}
	if second[0].Job.Generation != 2 {
		t.Fatal("manual reindex did not create a new generation")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_items WHERE batch_id=$1`, batch.ID); n != 21 {
		t.Fatalf("locked candidates vanished from durable enumeration: %d", n)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_items WHERE batch_id=$1 AND status='waiting'`, batch.ID); n != 20 {
		t.Fatalf("skipped lock became terminal outcome: %d", n)
	}
}

func TestIssue12OrphanCleanupRecountsOnlyAffectedScopeAndRetainsExecution(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	other := f.addActor(t)
	if _, err := f.documents.Create(ctx, f.actor.AccountID, m.Document{ID: uuid.NewString(), Title: "Retained metadata", CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatal(err)
	}
	doomed := f.accept(t, other, strings.Repeat("f", 64), "Removed namespace original")
	system := issue12Batch(t, f, other, true)
	namespace := issue12Batch(t, f, other, false)
	issue12Maintain(t, f, 4)
	leases, err := f.service.Claim(ctx, 1, time.Second, "issue12-orphan")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != doomed.ID {
		t.Fatalf("initial orphan fixture admission: %+v %v", leases, err)
	}
	if err = f.service.Delete(ctx, other, doomed.ID); err != nil {
		t.Fatal(err)
	}
	tx, err := f.connection.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	for _, query := range []string{`DELETE FROM sessions WHERE user_id=$1`, `DELETE FROM memberships WHERE user_id=$1`, `DELETE FROM users WHERE id=$1`} {
		if _, err = tx.Exec(ctx, query, other.UserID); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = tx.Exec(ctx, `DELETE FROM accounts WHERE id=$1`, other.AccountID); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	issue12Maintain(t, f, 4)
	aggregate, err := f.service.Batch(ctx, f.actor, true, system.ID)
	if err != nil || aggregate.Status != "succeeded" || aggregate.Discovered != 1 || aggregate.Skipped != 1 || aggregate.Waiting != 0 || aggregate.Running != 0 {
		t.Fatalf("orphan sweep left stale system aggregate: %+v %v", aggregate, err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches WHERE id=$1`, namespace.ID); n != 0 {
		t.Fatal("orphan namespace batch retained")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_jobs WHERE account_id=$1`, other.AccountID); n != 0 {
		t.Fatal("orphan title-free job evidence retained")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches WHERE id=$1 AND requester_id IS NULL`, system.ID); n != 1 {
		t.Fatal("deleted requester UUID retained")
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_executions WHERE account_id=$1 AND closed_at IS NULL`, other.AccountID); n != 1 {
		t.Fatal("namespace cleanup freed unknown execution capacity")
	}
}

func TestIssue12ManualReindexRequiresFreshExtractionAndPreservesCorrections(t *testing.T) {
	for _, correction := range []string{"", "  Exact human correction\r\n"} {
		t.Run(fmt.Sprintf("empty=%t", correction == ""), func(t *testing.T) {
			f := newIngestionFixture(t)
			ctx := t.Context()
			doc := f.accept(t, f.actor, strings.Repeat("1", 64), "Retained original")
			f.ready(t, doc, "Initial machine text", unitVector(0))
			original, err := f.repository.Reference(ctx, f.actor, doc.ID)
			if err != nil {
				t.Fatal(err)
			}
			corrected, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: 1, Text: correction})
			if err != nil {
				t.Fatal(err)
			}
			if correction != "" {
				job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 2}
				f.admit(t, job)
				if _, err = f.service.Work(ctx, job, "embedding"); err != nil {
					t.Fatal(err)
				}
				chunks, err := m.OCRChunks(correction)
				if err != nil {
					t.Fatal(err)
				}
				for i := range chunks {
					chunks[i].Vector = unitVector(0)
				}
				if err = f.service.SaveEmbeddings(ctx, job, corrected.Revision, m.DefaultConfiguration().EmbeddingSpace(), chunks); err != nil {
					t.Fatal(err)
				}
				if err = f.service.Publish(ctx, job, corrected.Revision); err != nil {
					t.Fatal(err)
				}
				f.closeTerminal(t)
			}
			batch := issue12Batch(t, f, f.actor, false)
			leases, err := f.service.Claim(ctx, 1, time.Second, "issue12-reextract")
			if err != nil || len(leases) != 1 || leases[0].Job.Generation != 3 {
				t.Fatalf("ready correction incorrectly satisfied full-reindex intent: %+v %v", leases, err)
			}
			job := leases[0].Job
			work, err := f.service.Work(ctx, job, "extracting")
			if err != nil || work.Stage != "extracting" {
				t.Fatalf("full reindex bypassed extraction: %+v %v", work, err)
			}
			if err = f.service.SaveExtraction(ctx, job, work.Revision, "Fresh machine from unchanged original"); err != nil {
				t.Fatal(err)
			}
			result, err := f.service.OCR(ctx, f.actor, doc.ID)
			if err != nil || result.Text == nil || *result.Text != correction || result.Revision != corrected.Revision {
				t.Fatalf("fresh extraction rewrote human correction: %+v %v", result, err)
			}
			if correction != "" {
				chunks, err := m.OCRChunks(correction)
				if err != nil {
					t.Fatal(err)
				}
				for i := range chunks {
					chunks[i].Vector = unitVector(0)
				}
				if err = f.service.SaveEmbeddings(ctx, job, corrected.Revision, m.DefaultConfiguration().EmbeddingSpace(), chunks); err != nil {
					t.Fatal(err)
				}
			}
			if err = f.service.Publish(ctx, job, corrected.Revision); err != nil {
				t.Fatal(err)
			}
			f.exec(t, `UPDATE document_reindex_items SET next_check_at=clock_timestamp() WHERE batch_id=$1`, batch.ID)
			issue12Maintain(t, f, 2)
			outcome, err := f.service.Batch(ctx, f.actor, false, batch.ID)
			if err != nil || outcome.Status != "succeeded" || outcome.Succeeded != 1 || outcome.Skipped != 0 {
				t.Fatalf("successful fresh full ingestion not reflected by batch: %+v %v", outcome, err)
			}
			after, err := f.repository.Reference(ctx, f.actor, doc.ID)
			if err != nil || after.File.SHA256 != original.File.SHA256 || after.File.Size != original.File.Size || after.Location != "final" {
				t.Fatalf("reindex changed original identity: %+v %v", after, err)
			}
			if n := issue12Count(t, f, `SELECT count(*) FROM documents d JOIN document_processing_jobs j ON j.document_id=d.id JOIN document_reindex_batches b ON b.id=$2 WHERE d.id=$1 AND d.ocr_machine_text='Fresh machine from unchanged original' AND d.machine_extraction_fingerprint=b.configuration_fingerprint AND d.machine_extraction_sequence=j.generation_sequence AND j.generation=3 AND j.requires_extraction AND j.generation_sequence>b.cutoff_sequence AND j.status='succeeded'`, doc.ID, batch.ID); n != 1 {
				t.Fatal("fresh extraction provenance or immutable full-ingestion evidence missing")
			}
			history, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{DocumentID: doc.ID, Pipeline: "ingestion"})
			if err != nil || len(history.Items) != 3 {
				t.Fatalf("generation history was lost: %+v %v", history, err)
			}
		})
	}
}

func TestIssue12BatchCutoffCannotOvertakePausedMetadataAcceptance(t *testing.T) {
	f := newIngestionFixture(t)
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	batchActor := f.addActor(t)
	c, err := f.service.GetProcessingConfiguration(ctx, batchActor)
	if err != nil {
		t.Fatal(err)
	}
	gate := time.Now().UnixNano()
	hold, err := f.source.Database().Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer hold.Rollback(context.Background())
	if _, err = hold.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, gate); err != nil {
		t.Fatal(err)
	}
	f.exec(t, fmt.Sprintf(`CREATE FUNCTION pause_issue12_acceptance() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_advisory_xact_lock(%d); RETURN NEW; END $$`, gate))
	f.exec(t, `CREATE TRIGGER pause_issue12_acceptance BEFORE INSERT ON documents FOR EACH ROW EXECUTE FUNCTION pause_issue12_acceptance()`)
	created := make(chan error, 1)
	document := m.Document{ID: uuid.NewString(), Title: "Accepted before batch", CreatedAt: time.Now().UTC()}
	go func() { _, err := f.documents.Create(ctx, f.actor.AccountID, document); created <- err }()
	ownsCoordination := false
	for !ownsCoordination {
		probe, err := f.source.Database().Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var acquired bool
		err = probe.QueryRow(ctx, `SELECT pg_try_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':document-processing',0))`).Scan(&acquired)
		probe.Rollback(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		ownsCoordination = !acquired
		if !ownsCoordination {
			select {
			case <-ctx.Done():
				t.Fatal("creator never entered coordinated acceptance")
			case <-time.After(5 * time.Millisecond):
			}
		}
	}
	request := m.DocumentReindexRequest{RequestID: uuid.NewString(), ConfigurationRevision: c.Revision}
	accepted := make(chan error, 1)
	go func() { _, err := f.service.CreateBatch(ctx, batchActor, true, request); accepted <- err }()
	for waiting := false; !waiting; {
		if err = f.connection.QueryRow(ctx, `WITH key AS (SELECT hashtextextended(current_database()||':'||current_schema()||':document-processing',0) AS value)
SELECT EXISTS(SELECT 1 FROM pg_locks,key WHERE locktype='advisory' AND NOT granted AND objsubid=1
AND classid=((key.value>>32)&4294967295)::oid AND objid=(key.value&4294967295)::oid)`).Scan(&waiting); err != nil {
			t.Fatal(err)
		}
		if !waiting {
			select {
			case err := <-accepted:
				t.Fatalf("batch overtook uncommitted coordinated creator: %v", err)
			case <-ctx.Done():
				t.Fatal("batch never waited for the acceptance coordination lock")
			case <-time.After(5 * time.Millisecond):
			}
		}
	}
	if err = hold.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err = <-created; err != nil {
		t.Fatal(err)
	}
	if err = <-accepted; err != nil {
		t.Fatal(err)
	}
	issue12Maintain(t, f, 2)
	if n := issue12Count(t, f, `SELECT count(*) FROM document_reindex_items WHERE batch_id=$1 AND document_id=$2`, request.RequestID, document.ID); n != 1 {
		t.Fatal("creator committed behind an advanced enumeration cutoff")
	}
}

func TestIssue12EmbeddingSpaceRejectsSameDigestDifferentAlgorithmsAndModel(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("2", 64), "Embedding provenance")
	job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	f.admit(t, job)
	if _, err := f.service.Work(ctx, job, "extracting"); err != nil {
		t.Fatal(err)
	}
	if err := f.service.SaveExtraction(ctx, job, 0, "provenance needle"); err != nil {
		t.Fatal(err)
	}
	correct := m.DefaultConfiguration().EmbeddingSpace()
	for _, field := range []string{"model", "input", "indexing"} {
		wrong := correct
		switch field {
		case "model":
			wrong.Model = "other-model:same-digest"
		case "input":
			wrong.EmbeddingInputRevision = "different-prefix"
		case "indexing":
			wrong.IndexingRevision = "different-vector-meaning"
		}
		err := f.service.SaveEmbeddings(ctx, job, 1, wrong, []m.DocumentChunk{{Text: "provenance needle", Vector: unitVector(0)}})
		var failure m.DocumentProcessingError
		if !errors.As(err, &failure) || failure.Code != "configuration_unavailable" {
			t.Fatalf("same-digest wrong %s was accepted: %v", field, err)
		}
		if n := issue12Count(t, f, `SELECT count(*) FROM document_chunks WHERE document_id=$1 AND embedding IS NOT NULL`, doc.ID); n != 0 {
			t.Fatal("rejected embedding space partially wrote vectors")
		}
	}
	if err := f.service.SaveEmbeddings(ctx, job, 1, correct, []m.DocumentChunk{{Text: "provenance needle", Vector: unitVector(0)}}); err != nil {
		t.Fatal(err)
	}
	if err := f.service.Publish(ctx, job, 1); err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"model", "input", "indexing"} {
		retained := m.DefaultConfiguration()
		switch field {
		case "model":
			retained.EmbeddingModel = "old-model:same-digest"
		case "input":
			retained.EmbeddingInputRevision = "old-input-prefix"
		case "indexing":
			retained.IndexingRevision = "old-vector-meaning"
		}
		retained.Fingerprint, _ = retained.CanonicalFingerprint()
		snapshot, err := json.Marshal(retained)
		if err != nil {
			t.Fatal(err)
		}
		f.exec(t, `UPDATE document_processing SET configuration=$2 WHERE document_id=$1`, doc.ID, snapshot)
		query, err := (m.DocumentSearchInput{Query: "needle", Mode: "semantic", Space: correct}).Normalize()
		if err != nil {
			t.Fatal(err)
		}
		matches, err := f.search(ctx, f.actor, query, unitVector(0))
		if err != nil || matches.Total != nil || len(matches.Items) != 0 {
			t.Fatalf("semantic search included same-digest incompatible %s: %+v %v", field, matches, err)
		}
		ocr, err := f.service.OCR(ctx, f.actor, doc.ID)
		if err != nil || ocr.SemanticIndexing != "pending" {
			t.Fatalf("OCR advertised obsolete %s vector space ready: %+v %v", field, ocr, err)
		}
		query.Mode = "fulltext"
		matches, err = f.search(ctx, f.actor, query, nil)
		if err != nil || matches.Total == nil || *matches.Total != 1 {
			t.Fatalf("incompatible vectors hid current lexical text: %+v %v", matches, err)
		}
	}
}

func TestIssue12TwoDispatchersRetainSupersededReservationUntilVerifiedClosure(t *testing.T) {
	f := newIngestionFixture(t)
	occupyDocumentCapacity(t, f, m.MaxConcurrentProcessing-1)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("3", 64), "Superseded admission")
	f.accept(t, f.actor, strings.Repeat("4", 64), "Independent waiting original")
	initial, err := f.service.Claim(ctx, 1, time.Second, "issue12-two-dispatchers")
	if err != nil || len(initial) != 1 {
		t.Fatalf("initial admission: %+v %v", initial, err)
	}
	old := initial[0]
	if _, err = f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: 0, Text: ""}); err != nil {
		t.Fatal(err)
	}
	result := make(chan struct {
		leases []m.DocumentOutboxLease
		err    error
	}, 2)
	claim := func() {
		leases, err := f.service.Claim(ctx, 1, time.Second, "issue12-two-dispatchers")
		result <- struct {
			leases []m.DocumentOutboxLease
			err    error
		}{leases, err}
	}
	go claim()
	go claim()
	for range 2 {
		got := <-result
		if got.err != nil || len(got.leases) != 0 {
			t.Fatalf("supersession freed unknown execution under concurrent dispatch: %+v %v", got.leases, got.err)
		}
	}
	run := uuid.NewString()
	if err = f.repository.Acknowledge(ctx, old, old.WorkflowID, run); err != nil {
		t.Fatalf("late acknowledgement lost superseded execution ownership: %v", err)
	}
	pending := issue12Pending(t, f, old.Job)
	if pending.RunID != run {
		t.Fatal("known run identity discarded after supersession")
	}
	if err = f.service.ResolveExecution(ctx, pending, run, "processing_failed", false); err != nil {
		t.Fatal(err)
	}
	history, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{DocumentID: doc.ID})
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, j := range history.Items {
		if j.Generation != nil && *j.Generation == 1 {
			found = true
			if j.Status != "superseded" {
				t.Fatalf("closure rewrote superseded outcome: %+v", j)
			}
		}
	}
	if !found {
		t.Fatal("superseded history vanished")
	}
	go claim()
	go claim()
	admitted := 0
	for range 2 {
		got := <-result
		if got.err != nil {
			t.Fatal(got.err)
		}
		admitted += len(got.leases)
		for _, lease := range got.leases {
			if lease.Job == old.Job {
				t.Fatal("closed old generation restarted")
			}
		}
	}
	if admitted != 1 {
		t.Fatalf("concurrent dispatchers acquired %d shared slots", admitted)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing_executions WHERE closed_at IS NULL`); n != m.MaxConcurrentProcessing {
		t.Fatalf("shared admission ledger has %d active rows", n)
	}
}

func TestIssue12EmptyCorrectionAfterDriftCannotSatisfyAutomaticExtraction(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("5", 64), "Old machine provenance")
	f.ready(t, doc, "Old machine source", unitVector(0))
	c, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil {
		t.Fatal(err)
	}
	c.Language = "eng"
	changed, err := f.service.SetProcessingConfiguration(ctx, f.actor, c)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: 1, Text: ""}); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing p JOIN documents d ON d.id=p.document_id WHERE d.id=$1 AND p.state='ready' AND NOT p.requires_extraction AND p.configuration->>'Fingerprint'=$2 AND d.machine_extraction_fingerprint<>$2`, doc.ID, changed.Fingerprint); n != 1 {
		t.Fatal("fixture did not retain old machine evidence under new empty correction")
	}
	leases, err := f.service.Claim(ctx, 1, time.Second, "issue12-automatic-extraction")
	if err != nil || len(leases) != 1 || leases[0].Job.Generation != 3 || leases[0].Job.DocumentID != doc.ID {
		t.Fatalf("empty current correction incorrectly skipped old machine extraction: %+v %v", leases, err)
	}
	work, err := f.service.Work(ctx, leases[0].Job, "extracting")
	if err != nil || work.Configuration.Fingerprint != changed.Fingerprint {
		t.Fatalf("automatic extraction failed to adopt target: %+v %v", work, err)
	}
}

func TestIssue12AlreadyCurrentAutomaticBatchAggregatesAllSchedulerSkips(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	for i := 0; i < 2; i++ {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+90), fmt.Sprintf("Already current %d", i))
		f.ready(t, doc, "Stored current extraction", unitVector(0))
	}
	original, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil {
		t.Fatal(err)
	}
	changed := original
	changed.Language = "eng"
	if _, err = f.service.SetProcessingConfiguration(ctx, f.actor, changed); err != nil {
		t.Fatal(err)
	}
	restored, err := f.service.SetProcessingConfiguration(ctx, f.actor, original)
	if err != nil {
		t.Fatal(err)
	}
	leases, err := f.service.Claim(ctx, 1, time.Second, "issue12-all-current")
	if err != nil || len(leases) != 0 {
		t.Fatalf("current ready originals were unnecessarily admitted: %+v %v", leases, err)
	}
	issue12Maintain(t, f, 3)
	batch, err := f.service.Batch(ctx, f.actor, true, restored.AutomaticBatchID)
	if err != nil || batch.Status != "succeeded" || batch.Discovered != 2 || batch.Skipped != 2 || batch.Waiting != 0 || batch.Running != 0 || batch.FinishedAt == nil {
		t.Fatalf("scheduler-only skips left stale aggregate: %+v %v", batch, err)
	}
	if n := issue12Count(t, f, `SELECT count(*) FROM document_processing WHERE generation<>1`); n != 0 {
		t.Fatal("return to prior compatible pipeline created unnecessary generations")
	}
}
