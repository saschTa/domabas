//go:build integration

package repos_test

import (
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func TestEmailExtractionEvidencePersistsWithoutInventedOCR(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	reservation, err := f.repository.Reserve(ctx, f.actor, m.DocumentUploadReservation{ExpiresAt: time.Now().Add(5 * time.Minute), ID: uuid.NewString(), AccountID: f.actor.AccountID, UploaderID: f.actor.UserID})
	if err != nil {
		t.Fatal(err)
	}
	reference := m.DocumentFileReference{AccountID: f.actor.AccountID, UploaderID: f.actor.UserID, DocumentID: reservation.ID, Location: "staged", File: m.DocumentFile{OriginalFilename: "mail.eml", MediaType: "message/rfc822", Size: 128, SHA256: strings.Repeat("a", 64), UploaderID: f.actor.UserID}}
	if err = f.repository.RecordStaged(ctx, f.actor, reservation.ID, reference); err != nil {
		t.Fatal(err)
	}
	metadata, err := (m.DocumentMetadata{Title: "An email", Kind: "email"}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	doc, err := f.acceptReservation(ctx, f.actor, reservation.ID, metadata, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	if doc.Processing.ExtractionMethod != "" {
		t.Fatal("queued email invented extraction")
	}
	job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
	f.admit(t, job)
	work, err := f.service.Work(ctx, job, "extracting")
	if err != nil {
		t.Fatal(err)
	}
	if err = f.service.SaveExtraction(ctx, job, work.Revision, "email text"); err != nil {
		t.Fatal(err)
	}
	processing, err := f.service.Processing(ctx, f.actor, doc.ID)
	if err != nil {
		t.Fatal(err)
	}
	if processing.ExtractionMethod != "mime" || processing.ExtractionEngine != "domabas-mime" || processing.ExtractionEngineVersion != "1" {
		t.Fatalf("processing evidence %+v", processing)
	}
	fetched, err := f.documents.Get(ctx, f.actor.AccountID, doc.ID)
	if err != nil {
		t.Fatal(err)
	}
	if fetched.Processing.ExtractionMethod != "mime" {
		t.Fatal("document detail lost MIME evidence")
	}
	history, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{DocumentID: doc.ID})
	if err != nil {
		t.Fatal(err)
	}
	if len(history.Items) != 1 || history.Items[0].ExtractionMethod != "mime" || history.Items[0].ExtractionEngine != "domabas-mime" {
		t.Fatalf("history evidence %+v", history)
	}
	var method, engine, version string
	if err = f.connection.QueryRow(ctx, "SELECT machine_extraction_method,machine_extraction_engine,machine_extraction_engine_version FROM documents WHERE id=$1", doc.ID).Scan(&method, &engine, &version); err != nil {
		t.Fatal(err)
	}
	if method != "mime" || engine != "domabas-mime" || version != "1" {
		t.Fatalf("machine evidence %s/%s/%s", method, engine, version)
	}
	if err = f.repository.Fail(ctx, job, "processing_failed"); err != nil {
		t.Fatal(err)
	}
	retried, err := f.service.Retry(ctx, f.actor, doc.ID)
	if err != nil {
		t.Fatal(err)
	}
	if retried.ExtractionMethod != "" {
		t.Fatal("new queued retry inherited old extraction evidence")
	}
	history, err = f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{DocumentID: doc.ID})
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range history.Items {
		if item.Generation != nil && *item.Generation == 1 && item.ExtractionMethod != "mime" {
			t.Fatal("retry rewrote historical MIME evidence")
		}
		if item.Generation != nil && *item.Generation == 2 && item.ExtractionMethod != "" {
			t.Fatal("queued retry history invented evidence")
		}
	}
}
