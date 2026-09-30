//go:build integration

package repos_test

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/filesystem"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	repos "github.com/domabas/domabas/backend/internal/data/document/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	"github.com/google/uuid"
)

type deniedClaimPolicy struct{ denied string }

func (p deniedClaimPolicy) AllowsAuthority(_ string, _ bool, _ []string, _, claim string) bool {
	return claim != p.denied
}

func TestOCRAndDeleteRecheckEveryRequiredClaim(t *testing.T) {
	for _, operation := range []struct {
		name   string
		claims []string
		call   func(*services.DocumentIngestionService, context.Context, m.DocumentActor, string) error
	}{
		{"read", []string{"documents:read", "documents:ocr:read"}, func(r *services.DocumentIngestionService, ctx context.Context, actor m.DocumentActor, id string) error {
			_, err := r.OCR(ctx, actor, id)
			return err
		}},
		{"correct", []string{"documents:read", "documents:ocr:read", "documents:ocr:update"}, func(r *services.DocumentIngestionService, ctx context.Context, actor m.DocumentActor, id string) error {
			_, err := r.CorrectOCR(ctx, actor, id, m.DocumentOCRCorrection{Text: "correction"})
			return err
		}},
		{"delete", []string{"documents:read", "documents:delete"}, func(r *services.DocumentIngestionService, ctx context.Context, actor m.DocumentActor, id string) error {
			return r.Delete(ctx, actor, id)
		}},
	} {
		for _, claim := range operation.claims {
			t.Run(operation.name+"/"+claim, func(t *testing.T) {
				f := newIngestionFixture(t)
				doc := f.accept(t, f.actor, strings.Repeat("a", 64), "Authority")
				repository := services.NewDocumentIngestionService(f.repository, nil, nil, documentDeniedAuthority{authority: f.authority, claim: claim}, time.Now)
				if err := operation.call(repository, t.Context(), f.actor, doc.ID); !errors.Is(err, m.ErrForbidden) {
					t.Fatalf("missing %s permitted %s: %v", claim, operation.name, err)
				}
				ocr, err := f.service.OCR(t.Context(), f.actor, doc.ID)
				if err != nil || ocr.Revision != 0 || ocr.Text != nil {
					t.Fatalf("denied operation mutated document: %+v %v", ocr, err)
				}
			})
		}
	}
}

func TestOCRRoleGrantsRevocationAndNamespaceIsolation(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("b", 64), "Role changes")
	f.exec(t, "UPDATE memberships SET is_owner=false,role='viewer',claims='{}' WHERE account_id=$1 AND user_id=$2", f.actor.AccountID, f.actor.UserID)
	if _, err := f.service.OCR(ctx, f.actor, doc.ID); err != nil {
		t.Fatalf("viewer cannot read OCR: %v", err)
	}
	if _, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Text: "forbidden"}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("viewer corrected OCR: %v", err)
	}
	if err := f.service.Delete(ctx, f.actor, doc.ID); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("viewer deleted original: %v", err)
	}
	f.exec(t, "UPDATE memberships SET claims=ARRAY['documents:ocr:update','documents:delete'] WHERE account_id=$1 AND user_id=$2", f.actor.AccountID, f.actor.UserID)
	if _, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Text: "granted"}); err != nil {
		t.Fatal(err)
	}
	foreign := f.addActor(t)
	if _, err := f.service.OCR(ctx, foreign, doc.ID); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign OCR leaked: %v", err)
	}
	if _, err := f.service.CorrectOCR(ctx, foreign, doc.ID, m.DocumentOCRCorrection{Revision: 1, Text: "foreign"}); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign correction: %v", err)
	}
	if err := f.service.Delete(ctx, foreign, doc.ID); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign deletion: %v", err)
	}
	for _, revoke := range []struct {
		name, query string
		args        []any
	}{
		{"disabled membership", "UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2", []any{f.actor.AccountID, f.actor.UserID}},
		{"revoked session", "DELETE FROM sessions WHERE digest=$1", []any{f.actor.SessionDigest}},
	} {
		t.Run(revoke.name, func(t *testing.T) {
			f.exec(t, revoke.query, revoke.args...)
			if _, err := f.service.OCR(ctx, f.actor, doc.ID); !errors.Is(err, m.ErrUnauthorized) {
				t.Fatalf("revoked OCR read: %v", err)
			}
			if _, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: 1, Text: "revoked"}); !errors.Is(err, m.ErrUnauthorized) {
				t.Fatalf("revoked correction: %v", err)
			}
			if err := f.service.Delete(ctx, f.actor, doc.ID); !errors.Is(err, m.ErrUnauthorized) {
				t.Fatalf("revoked deletion: %v", err)
			}
			f.exec(t, "UPDATE memberships SET enabled=true WHERE account_id=$1 AND user_id=$2", f.actor.AccountID, f.actor.UserID)
		})
	}
}

func TestOCRCompareAndSwapSerializesCompetingCorrections(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("c", 64), "Competing editors")
	start := make(chan struct{})
	results := make(chan error, 2)
	var group sync.WaitGroup
	for _, text := range []string{"first editor", "second editor"} {
		group.Go(func() {
			<-start
			_, err := f.service.CorrectOCR(t.Context(), f.actor, doc.ID, m.DocumentOCRCorrection{Text: text})
			results <- err
		})
	}
	close(start)
	group.Wait()
	close(results)
	saved, conflict := 0, 0
	for err := range results {
		if err == nil {
			saved++
		} else if errors.Is(err, m.ErrConflict) {
			conflict++
		} else {
			t.Fatal(err)
		}
	}
	if saved != 1 || conflict != 1 {
		t.Fatalf("CAS outcomes saved=%d conflict=%d", saved, conflict)
	}
	var revision, generation, outbox int
	if err := f.connection.QueryRow(t.Context(), `SELECT d.ocr_revision,p.generation,(SELECT count(*) FROM document_outbox WHERE document_id=d.id) FROM documents d JOIN document_processing p ON p.document_id=d.id WHERE d.id=$1`, doc.ID).Scan(&revision, &generation, &outbox); err != nil || revision != 1 || generation != 2 || outbox != 1 {
		t.Fatalf("non-atomic correction: revision=%d generation=%d outbox=%d err=%v", revision, generation, outbox, err)
	}
}

func TestCorrectionFencesPausedExtractionEmbeddingAndPublication(t *testing.T) {
	for _, stage := range []string{"extracting", "embedding", "finalizing"} {
		t.Run(stage, func(t *testing.T) {
			f := newIngestionFixture(t)
			ctx := t.Context()
			doc := f.accept(t, f.actor, strings.Repeat("d", 64), "Paused worker")
			job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
			f.admit(t, job)
			if _, err := f.service.Work(ctx, job, "extracting"); err != nil {
				t.Fatal(err)
			}
			revision := int64(0)
			chunks := []m.DocumentChunk{{Text: "obsolete machine", Vector: unitVector(0)}}
			if stage != "extracting" {
				if err := f.service.SaveExtraction(ctx, job, 0, "obsolete machine"); err != nil {
					t.Fatal(err)
				}
				revision = 1
			}
			if stage == "finalizing" {
				if err := f.service.SaveEmbeddings(ctx, job, revision, m.DefaultConfiguration().EmbeddingSpace(), chunks); err != nil {
					t.Fatal(err)
				}
			}
			entered, release, done := make(chan struct{}), make(chan struct{}), make(chan error, 1)
			go func() {
				close(entered)
				<-release
				var err error
				switch stage {
				case "extracting":
					err = f.service.SaveExtraction(ctx, job, revision, "obsolete machine")
				case "embedding":
					err = f.service.SaveEmbeddings(ctx, job, revision, m.DefaultConfiguration().EmbeddingSpace(), chunks)
				default:
					err = f.service.Publish(ctx, job, revision)
				}
				done <- err
			}()
			<-entered
			_, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: revision, Text: "current correction"})
			close(release)
			if err != nil {
				t.Fatal(err)
			}
			if err := <-done; !errors.Is(err, m.ErrStaleJob) {
				t.Fatalf("paused %s overwrote correction: %v", stage, err)
			}
			ocr, err := f.service.OCR(ctx, f.actor, doc.ID)
			if err != nil || ocr.Text == nil || *ocr.Text != "current correction" || ocr.Revision != revision+1 {
				t.Fatalf("correction lost: %+v %v", ocr, err)
			}
		})
	}
}

type publicationBarrier struct{ entered, release chan struct{} }

func (p *publicationBarrier) Promote(ctx context.Context, ref records.DocumentContentReference) (records.DocumentContentReference, error) {
	close(p.entered)
	select {
	case <-ctx.Done():
		return ref, ctx.Err()
	case <-p.release:
		ref.Location = "final"
		return ref, nil
	}
}

func TestPublicationHoldsDocumentLockUntilCorrectionOrDeletionCanProceed(t *testing.T) {
	for _, remove := range []bool{false, true} {
		t.Run(fmt.Sprintf("delete=%v", remove), func(t *testing.T) {
			f := newIngestionFixture(t)
			ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
			defer cancel()
			doc := f.accept(t, f.actor, strings.Repeat("e", 64), "Publication lock")
			job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
			f.admit(t, job)
			if _, err := f.service.Work(ctx, job, "extracting"); err != nil {
				t.Fatal(err)
			}
			if err := f.service.SaveExtraction(ctx, job, 0, ""); err != nil {
				t.Fatal(err)
			}
			barrier := &publicationBarrier{make(chan struct{}), make(chan struct{})}
			var once sync.Once
			release := func() { once.Do(func() { close(barrier.release) }) }
			defer release()
			repository := services.NewDocumentIngestionService(repos.NewDocumentIngestionRepository(sources.NewDocumentIngestionDataSource(f.source.Database(), barrier, f.scheduler)), nil, documentFixtureProcessor{}, f.authority, time.Now)
			published := make(chan error, 1)
			go func() { published <- repository.Publish(ctx, job, 1) }()
			select {
			case <-barrier.entered:
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			mutated := make(chan error, 1)
			go func() {
				if remove {
					mutated <- f.service.Delete(ctx, f.actor, doc.ID)
				} else {
					_, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: 1, Text: "after publication"})
					mutated <- err
				}
			}()
			for {
				select {
				case err := <-mutated:
					t.Fatalf("mutation escaped publication lock: %v", err)
				default:
				}
				var blocked bool
				if err := f.connection.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND query='SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE' AND wait_event_type='Lock')`).Scan(&blocked); err != nil {
					t.Fatal(err)
				}
				if blocked {
					break
				}
				select {
				case <-time.After(10 * time.Millisecond):
				case <-ctx.Done():
					t.Fatal(ctx.Err())
				}
			}
			release()
			if err := <-published; err != nil {
				t.Fatal(err)
			}
			if err := <-mutated; err != nil {
				t.Fatal(err)
			}
			if err := repository.Publish(ctx, job, 1); !errors.Is(err, m.ErrStaleJob) {
				t.Fatalf("old publisher revived document: %v", err)
			}
			if remove {
				if _, err := f.service.OCR(ctx, f.actor, doc.ID); !errors.Is(err, m.ErrNotFound) {
					t.Fatalf("deleted document visible: %v", err)
				}
			} else {
				result, err := f.service.OCR(ctx, f.actor, doc.ID)
				if err != nil || result.Text == nil || *result.Text != "after publication" {
					t.Fatalf("publication lost correction: %+v %v", result, err)
				}
			}
		})
	}
}

func TestRetainedCleanupRetriesFilesystemFailureAndRemovesLatePublication(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc := f.accept(t, f.actor, strings.Repeat("f", 64), "Erased contents")
	base := t.TempDir()
	staged, final := filepath.Join(base, "staged"), filepath.Join(base, "final")
	store, err := filesystem.NewDocumentFileSystemDataSource(staged, final)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	relative := filepath.Join(f.actor.AccountID, f.actor.UserID, doc.ID)
	for _, root := range []string{staged, final} {
		if err := os.MkdirAll(filepath.Join(root, relative), 0700); err != nil {
			t.Fatal(err)
		}
	}
	original := filepath.Join(final, relative, "original")
	if err := os.Mkdir(original, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(original, "blocked"), []byte("forced removal failure"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staged, relative, "original"), []byte("staged content"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := f.service.Delete(ctx, f.actor, doc.ID); err != nil {
		t.Fatal(err)
	}
	service := services.NewDocumentIngestionService(f.repository, repos.NewDocumentContentRepository(store), nil, f.authority, time.Now)
	if err := service.ReapUploads(ctx); err == nil {
		t.Fatal("filesystem failure acknowledged as success")
	}
	var attempts int
	var due, leased bool
	if err := f.connection.QueryRow(ctx, "SELECT attempts,next_attempt_at>clock_timestamp(),lease_token IS NOT NULL FROM document_cleanup WHERE document_id=$1", doc.ID).Scan(&attempts, &due, &leased); err != nil || attempts != 1 || !due || leased {
		t.Fatalf("failure not durably rescheduled: %d %v %v %v", attempts, due, leased, err)
	}
	if err := os.Remove(filepath.Join(original, "blocked")); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(original); err != nil {
		t.Fatal(err)
	}
	for attempt := range 2 {
		if err := os.WriteFile(original, []byte("late original"), 0600); err != nil {
			t.Fatal(err)
		}
		temporary := original + "." + uuid.NewString() + ".tmp"
		if err := os.WriteFile(temporary, []byte("partial publication"), 0600); err != nil {
			t.Fatal(err)
		}
		f.exec(t, "UPDATE document_cleanup SET next_attempt_at=clock_timestamp()-interval '1 second' WHERE document_id=$1", doc.ID)
		if err := service.ReapUploads(ctx); err != nil {
			t.Fatal(err)
		}
		for _, path := range []string{original, temporary, filepath.Join(staged, relative, "original")} {
			if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("cleanup %d retained %s: %v", attempt, path, err)
			}
		}
		if err := f.connection.QueryRow(ctx, "SELECT attempts,next_attempt_at>clock_timestamp(),lease_token IS NOT NULL FROM document_cleanup WHERE document_id=$1", doc.ID).Scan(&attempts, &due, &leased); err != nil || attempts != 0 || !due || leased {
			t.Fatalf("cleanup identity was discarded: %d %v %v %v", attempts, due, leased, err)
		}
	}
}

func TestCleanupLeaseOwnershipExpiryAndDueOrdering(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	for i := range 23 {
		f.exec(t, `INSERT INTO document_cleanup(document_id,account_id,uploader_id,next_attempt_at) VALUES($1,$2,$3,clock_timestamp()-interval '1 minute'+$4*interval '1 millisecond')`, uuid.NewString(), f.actor.AccountID, f.actor.UserID, i)
	}
	first, err := f.repository.ReapDeleted(ctx, 1000)
	if err != nil || len(first) != 20 {
		t.Fatalf("cleanup batch not bounded to 20: %d %v", len(first), err)
	}
	second, err := f.repository.ReapDeleted(ctx, 20)
	if err != nil || len(second) != 3 {
		t.Fatalf("leased rows blocked remaining due work: %d %v", len(second), err)
	}
	lease := first[0]
	wrong := lease
	wrong.LeaseToken = uuid.NewString()
	if err := f.repository.DeletedReaped(ctx, wrong, m.PlanDocumentCleanup(wrong, true, time.Now())); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("foreign cleanup lease acknowledged: %v", err)
	}
	f.exec(t, "UPDATE document_cleanup SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE document_id=$1", lease.DocumentID)
	if err := f.repository.DeletedReaped(ctx, lease, m.PlanDocumentCleanup(lease, true, time.Now())); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("expired cleanup lease acknowledged: %v", err)
	}
	for _, item := range append(first[1:], second...) {
		if err := f.repository.DeletedReaped(ctx, item, m.PlanDocumentCleanup(item, true, time.Now())); err != nil {
			t.Fatal(err)
		}
	}
	reclaimed, err := f.repository.ReapDeleted(ctx, 20)
	if err != nil || len(reclaimed) != 1 || reclaimed[0].DocumentID != lease.DocumentID || reclaimed[0].LeaseToken == lease.LeaseToken {
		t.Fatalf("expired lease was not reissued without successful rows: %+v %v", reclaimed, err)
	}
	if err := f.repository.DeletedReaped(ctx, reclaimed[0], m.PlanDocumentCleanup(reclaimed[0], false, time.Now())); err != nil {
		t.Fatal(err)
	}
	if due, err := f.repository.ReapDeleted(ctx, 20); err != nil || len(due) != 0 {
		t.Fatalf("backoff or successful sweeps starved future work: %+v %v", due, err)
	}
}

func TestMetadataOnlyAndOverflowCorrectionsLeaveNoPartialMutation(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	doc, err := f.documents.Create(ctx, f.actor.AccountID, m.Document{ID: uuid.NewString(), Title: "Metadata only", CreatedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	ocr, err := f.service.OCR(ctx, f.actor, doc.ID)
	if err != nil || ocr.Reason == nil || *ocr.Reason != "no_original" || ocr.Text != nil {
		t.Fatalf("metadata document advertised OCR: %+v %v", ocr, err)
	}
	if _, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Text: "invented text"}); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("metadata document accepted correction: %v", err)
	}
	if err := f.service.Delete(ctx, f.actor, doc.ID); err != nil {
		t.Fatal(err)
	}
	var cleanup int
	if err := f.connection.QueryRow(ctx, "SELECT count(*) FROM document_cleanup WHERE document_id=$1", doc.ID).Scan(&cleanup); err != nil || cleanup != 0 {
		t.Fatalf("metadata deletion invented storage identity: %d %v", cleanup, err)
	}
	for _, field := range []string{"revision", "generation"} {
		t.Run(field, func(t *testing.T) {
			doc := f.accept(t, f.actor, fmt.Sprintf("%064x", len(field)), "Overflow")
			revision := int64(0)
			if field == "revision" {
				revision = math.MaxInt64
				f.exec(t, "UPDATE documents SET ocr_revision=$2 WHERE id=$1", doc.ID, revision)
				f.exec(t, "UPDATE document_processing SET ocr_revision=$2 WHERE document_id=$1", doc.ID, revision)
			} else {
				f.exec(t, "UPDATE document_processing SET generation=$2 WHERE document_id=$1", doc.ID, int64(math.MaxInt64))
			}
			if _, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Revision: revision, Text: "overflow"}); !errors.Is(err, m.ErrConflict) {
				t.Fatalf("overflow did not conflict: %v", err)
			}
			ocr, err := f.service.OCR(ctx, f.actor, doc.ID)
			if err != nil || ocr.Revision != revision || ocr.Text != nil {
				t.Fatalf("overflow partially committed: %+v %v", ocr, err)
			}
		})
	}
}
