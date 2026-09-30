//go:build integration

package repos_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestPDFUnlockPublicationFencesAndQueuesAtomically(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("a", 64), "Password PDF")
	f.exec(t, "UPDATE document_processing SET state='failed',stage='failed',failure_code='encrypted_pdf' WHERE document_id=$1", doc.ID)
	original, err := f.service.UnlockReference(t.Context(), f.actor, doc.ID, 1)
	if err != nil {
		t.Fatal(err)
	}
	candidate := original
	candidate.Location = "unlocked"
	candidate.File.Size = 321
	candidate.File.SHA256 = strings.Repeat("b", 64)
	foreign := f.addActor(t)
	if _, err = f.service.UnlockReference(t.Context(), foreign, doc.ID, 1); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign unlock: %v", err)
	}
	if _, err = f.completeUnlock(t.Context(), f.actor, original, candidate, 2); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale generation: %v", err)
	}
	current, err := f.repository.Reference(t.Context(), f.actor, doc.ID)
	if err != nil || current.File.SHA256 != original.File.SHA256 {
		t.Fatal("stale publication changed bytes", err)
	}
	f.exec(t, "UPDATE memberships SET is_owner=false,role='viewer',claims='{}' WHERE user_id=$1 AND account_id=$2", f.actor.UserID, f.actor.AccountID)
	if _, err = f.service.Unlock(t.Context(), f.actor, doc.ID, 1, "password"); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("revoked authority: %v", err)
	}
	f.exec(t, "UPDATE memberships SET is_owner=true WHERE user_id=$1 AND account_id=$2", f.actor.UserID, f.actor.AccountID)
	processing, err := f.completeUnlock(t.Context(), f.actor, original, candidate, 1)
	if err != nil || processing.Generation != 2 || processing.State != "queued" || processing.FailureCode != "" {
		t.Fatalf("unlock not queued: %+v %v", processing, err)
	}
	current, err = f.repository.Reference(t.Context(), f.actor, doc.ID)
	if err != nil || current.Location != "unlocked" || current.File.SHA256 != candidate.File.SHA256 || current.File.Size != 321 || current.File.OriginalFilename != original.File.OriginalFilename {
		t.Fatalf("invalid stored reference: %+v %v", current, err)
	}
	var outboxes int
	if err = f.connection.QueryRow(t.Context(), "SELECT count(*) FROM document_outbox WHERE document_id=$1 AND generation=2", doc.ID).Scan(&outboxes); err != nil || outboxes != 1 {
		t.Fatalf("missing durable work: %d %v", outboxes, err)
	}
	if _, err = f.completeUnlock(t.Context(), f.actor, original, candidate, 1); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("concurrent unlock accepted: %v", err)
	}
}

func TestPDFUnlockDuplicateRollsBackReferenceAndGeneration(t *testing.T) {
	f := newIngestionFixture(t)
	duplicate := strings.Repeat("c", 64)
	f.accept(t, f.actor, duplicate, "Existing unlocked file")
	doc := f.accept(t, f.actor, strings.Repeat("d", 64), "Locked file")
	f.exec(t, "UPDATE document_processing SET state='failed',stage='failed',failure_code='encrypted_pdf' WHERE document_id=$1", doc.ID)
	original, err := f.service.UnlockReference(t.Context(), f.actor, doc.ID, 1)
	if err != nil {
		t.Fatal(err)
	}
	candidate := original
	candidate.Location = "unlocked"
	candidate.File.SHA256 = duplicate
	if _, err = f.completeUnlock(t.Context(), f.actor, original, candidate, 1); !errors.Is(err, m.ErrDuplicate) {
		t.Fatalf("duplicate allowed: %v", err)
	}
	current, err := f.repository.Reference(t.Context(), f.actor, doc.ID)
	if err != nil || current.File.SHA256 != original.File.SHA256 || current.Location != original.Location {
		t.Fatalf("failed commit changed original: %+v %v", current, err)
	}
	processing, err := f.service.Processing(t.Context(), f.actor, doc.ID)
	if err != nil || processing.Generation != 1 || processing.FailureCode != "encrypted_pdf" {
		t.Fatalf("failed commit queued work: %+v %v", processing, err)
	}
	if err = f.service.Delete(t.Context(), f.actor, doc.ID); err != nil {
		t.Fatal(err)
	}
	if _, err = f.completeUnlock(t.Context(), f.actor, original, candidate, 1); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("deleted document resurrected: %v", err)
	}
}

func (f *ingestionFixture) completeUnlock(ctx context.Context, a m.DocumentActor, original, unlocked m.DocumentFileReference, generation int64) (m.DocumentProcessing, error) {
	facts, err := f.repository.RetryFacts(ctx, a, original.DocumentID)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	command, err := m.PlanDocumentRetry(facts)
	if err != nil {
		return m.DocumentProcessing{}, err
	}
	return f.repository.CompleteUnlock(ctx, a, original, unlocked, generation, command)
}
