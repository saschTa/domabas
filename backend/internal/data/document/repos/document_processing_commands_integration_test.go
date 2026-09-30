//go:build integration

package repos_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestProcessingCommandsRejectChangedRoutingAndManualFacts(t *testing.T) {
	for _, field := range []string{"split_pipeline", "unlimited_inference", "ocr_manual_text", "retained_llm"} {
		t.Run(field, func(t *testing.T) {
			f := newIngestionFixture(t)
			ctx := t.Context()
			doc := f.accept(t, f.actor, strings.Repeat("b", 64), "Processing command fence")
			job := m.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
			f.admit(t, job)
			if _, err := f.service.Work(ctx, job, "extracting"); err != nil {
				t.Fatal(err)
			}
			work, err := f.repository.Work(ctx, job, "extracting")
			if err != nil {
				t.Fatal(err)
			}
			command, err := m.PlanDocumentExtraction(work, work.Revision, m.DocumentExtraction{Text: "planned machine content"})
			if err != nil {
				t.Fatal(err)
			}
			switch field {
			case "split_pipeline":
				f.exec(t, "UPDATE document_processing SET split_pipeline=NOT split_pipeline WHERE account_id=$1 AND document_id=$2", job.AccountID, job.DocumentID)
			case "unlimited_inference":
				f.exec(t, "UPDATE document_processing SET unlimited_inference=NOT unlimited_inference WHERE account_id=$1 AND document_id=$2", job.AccountID, job.DocumentID)
			case "ocr_manual_text":
				f.exec(t, "UPDATE documents SET ocr_manual_text='retained correction' WHERE account_id=$1 AND id=$2", job.AccountID, job.DocumentID)
			case "retained_llm":
				configuration := work.Configuration
				configuration.LLM.Enabled = true
				configuration.Fingerprint, err = configuration.CanonicalFingerprint()
				if err != nil {
					t.Fatal(err)
				}
				snapshot, err := json.Marshal(configuration)
				if err != nil {
					t.Fatal(err)
				}
				f.exec(t, "UPDATE document_processing SET configuration=$3 WHERE account_id=$1 AND document_id=$2", job.AccountID, job.DocumentID, snapshot)
			}
			if err = f.repository.SaveExtractionEvidence(ctx, command); !errors.Is(err, m.ErrStaleJob) {
				t.Fatalf("changed %s accepted: %v", field, err)
			}
			var machine *string
			if err = f.connection.QueryRow(ctx, "SELECT ocr_machine_text FROM documents WHERE account_id=$1 AND id=$2", job.AccountID, job.DocumentID).Scan(&machine); err != nil || machine != nil {
				t.Fatalf("partial extraction commit: %v %v", machine, err)
			}
		})
	}
}

func TestReindexMaintenanceRejectsStalePlanAndCountsRetainedItemsOnce(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	f.accept(t, f.actor, strings.Repeat("c", 64), "Retained enumeration")
	issue12Maintain(t, f, 3)
	batch := issue12Batch(t, f, f.actor, false)
	facts, err := f.repository.ReindexMaintenanceFacts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if facts.Enumeration == nil || facts.Enumeration.BatchID != batch.ID {
		t.Fatalf("missing enumeration: %+v", facts)
	}
	command := m.PlanDocumentReindexMaintenance(facts)
	if err = f.repository.MaintainProcessing(ctx, command); err != nil {
		t.Fatal(err)
	}
	if err = f.repository.MaintainProcessing(ctx, command); !errors.Is(err, m.ErrConflict) {
		t.Fatalf("stale cursor accepted: %v", err)
	}
	f.exec(t, "UPDATE document_reindex_batches SET cursor_sequence=0 WHERE id=$1", batch.ID)
	if err = f.service.MaintainProcessing(ctx); err != nil {
		t.Fatal(err)
	}
	var discovered, waiting, cursor int64
	if err = f.connection.QueryRow(ctx, "SELECT discovered,waiting,cursor_sequence FROM document_reindex_batches WHERE id=$1", batch.ID).Scan(&discovered, &waiting, &cursor); err != nil {
		t.Fatal(err)
	}
	if discovered != 1 || waiting != 1 || cursor <= 0 {
		t.Fatalf("retained item counted twice: discovered=%d waiting=%d cursor=%d", discovered, waiting, cursor)
	}
}
