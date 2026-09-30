//go:build integration

package repos_test

import (
	"errors"
	documentservices "github.com/domabas/domabas/backend/internal/domain/document/services"
	invoiceservices "github.com/domabas/domabas/backend/internal/domain/invoice/services"
	"reflect"
	"strings"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	documentrepos "github.com/domabas/domabas/backend/internal/data/document/repos"
	invoicesources "github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	invoicerepos "github.com/domabas/domabas/backend/internal/data/invoice/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func documentAIService(source *sources.DocumentDataSource) *documentservices.DocumentAIService {
	return documentservices.NewDocumentAIService(documentrepos.NewDocumentAIRepository(source))
}

type aiIndependentChunk struct {
	Position int
	Content  string
	Vector   []float64
	Digest   string
}

func aiIndependentEnableProperties(t *testing.T, f *ingestionFixture) m.DocumentProcessingConfiguration {
	t.Helper()
	current, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
	if err != nil {
		t.Fatal(err)
	}
	invoiceEnabled := false
	configuration, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{
		Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision,
		LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: true, InvoiceEnabled: &invoiceEnabled, Provider: "ollama", Model: "qwen3.5:4b"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return configuration
}

func aiIndependentClaim(t *testing.T, source *sources.DocumentDataSource, documentID string) m.DocumentOutboxLease {
	t.Helper()
	leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != documentID || leases[0].Job.AIAttempt < 1 {
		t.Fatalf("claim independent AI: %+v %v", leases, err)
	}
	if err := source.AIAcknowledge(t.Context(), leases[0], leases[0].WorkflowID, uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	return leases[0]
}

func TestAIReservedOrFailedAttemptDoesNotChangePublishedSearch(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	configuration := aiIndependentEnableProperties(t, f)
	first := f.accept(t, f.actor, strings.Repeat("2", 64), "Searchable during AI")
	aiIndependentReady(t, f, first, "independent search publication")
	before := aiIndependentPublished(t, f, first.ID)
	second := f.accept(t, f.actor, strings.Repeat("3", 64), "Searchable after blocked AI")
	aiIndependentReady(t, f, second, "independent search publication continues")
	lease := aiIndependentClaim(t, source, first.ID)
	aiIndependentAssertSearchable(t, f, first.ID)
	aiIndependentAssertSearchable(t, f, second.ID)
	if leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker"); err != nil || len(leases) != 0 {
		t.Fatalf("active AI attempt did not retain only its own bounded admission: %+v %v", leases, err)
	}
	if err := source.AIFail(t.Context(), lease.Job, "inference_unavailable"); err != nil {
		t.Fatal(err)
	}
	if after := aiIndependentPublished(t, f, first.ID); !reflect.DeepEqual(before, after) {
		t.Fatalf("failed AI changed ingestion: before=%+v after=%+v", before, after)
	}
	aiIndependentAssertSearchable(t, f, first.ID)
	request := m.DocumentReindexRequest{RequestID: uuid.NewString(), ConfigurationRevision: configuration.Revision}
	retried, err := f.service.RetryAI(t.Context(), f.actor, first.ID, request)
	if err != nil || retried.Attempt != lease.Job.AIAttempt+1 || retried.Status != "queued" {
		t.Fatalf("independent AI retry: %+v %v", retried, err)
	}
	replayed, err := f.service.RetryAI(t.Context(), f.actor, first.ID, request)
	if err != nil || replayed.JobID != retried.JobID || replayed.Attempt != retried.Attempt {
		t.Fatalf("uncertain retry created duplicate AI attempt: %+v %v", replayed, err)
	}
	if after := aiIndependentPublished(t, f, first.ID); !reflect.DeepEqual(before, after) {
		t.Fatalf("AI retry replaced ingestion: before=%+v after=%+v", before, after)
	}
	if err := source.AIFail(t.Context(), lease.Job, "processing_failed"); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("old AI execution modified its replacement: %v", err)
	}
	if leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker"); err != nil || len(leases) != 0 {
		t.Fatalf("failed execution released AI capacity before confirmed closure: %+v %v", leases, err)
	}
	pending, err := source.AIPending(t.Context(), 100)
	if err != nil || len(pending) != 1 || pending[0].Job != lease.Job {
		t.Fatalf("failed AI lost retained execution ownership: %+v %v", pending, err)
	}
	if err := documentAIService(source).ResolveExecution(t.Context(), pending[0], uuid.NewString(), "processing_incomplete", false); !errors.Is(err, m.ErrStaleJob) {
		t.Fatalf("foreign run closed an owned AI execution: %v", err)
	}
	if err := documentAIService(source).ResolveExecution(t.Context(), pending[0], pending[0].RunID, "processing_incomplete", true); err != nil {
		t.Fatal(err)
	}
	if leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker"); err != nil || len(leases) != 0 {
		t.Fatalf("missing unlimited workflow history incorrectly proved closure: %+v %v", leases, err)
	}
	f.exec(t, "UPDATE document_ai_jobs SET next_check_at=clock_timestamp() WHERE id=$1", lease.ID)
	pending, err = source.AIPending(t.Context(), 100)
	if err != nil || len(pending) != 1 {
		t.Fatalf("AI closure reconciliation: %+v %v", pending, err)
	}
	if err := documentAIService(source).ResolveExecution(t.Context(), pending[0], pending[0].RunID, "processing_incomplete", false); err != nil {
		t.Fatal(err)
	}
	leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != second.ID {
		t.Fatalf("confirmed AI closure did not release its own capacity: %+v %v", leases, err)
	}
}

func TestAIPropertyPublicationFencesConcurrentDocumentChanges(t *testing.T) {
	for _, scenario := range []string{"metadata cleared", "OCR corrected", "document deleted"} {
		t.Run(scenario, func(t *testing.T) {
			f := newIngestionFixture(t)
			source := llmSource(t, f)
			aiIndependentEnableProperties(t, f)
			doc := f.accept(t, f.actor, strings.Repeat("4", 64), "Keep user title")
			aiIndependentReady(t, f, doc, "independent search publication")
			lease := aiIndependentClaim(t, source, doc.ID)
			invoices := invoiceservices.NewInvoiceService(invoicerepos.NewInvoiceRepository(invoicesources.NewInvoiceDataSource(f.source.Database())), nil, nil, f.authority, nil)
			invoiceWork, err := invoices.Work(t.Context(), lease.Job)
			if err != nil {
				t.Fatal(err)
			}
			invoiceWork.Skipped = true
			if err := invoices.Save(t.Context(), invoiceWork, nil); err != nil {
				t.Fatal(err)
			}
			properties := documentrepos.NewDocumentPropertyRepository(source)
			work, err := properties.Work(t.Context(), lease.Job)
			if err != nil || work.Stage != "enriching" {
				t.Fatalf("AI property work not independently active: %+v %v", work, err)
			}
			switch scenario {
			case "metadata cleared":
				empty := ""
				_, err = f.service.Update(t.Context(), f.actor, doc.ID, m.DocumentMetadataPatch{Description: &empty})
			case "OCR corrected":
				_, err = f.service.CorrectOCR(t.Context(), f.actor, doc.ID, m.DocumentOCRCorrection{Revision: work.Revision, Text: "corrected effective OCR"})
			case "document deleted":
				err = f.service.Delete(t.Context(), f.actor, doc.ID)
			}
			if err != nil {
				t.Fatal(err)
			}
			work.NextStage = "complete"
			err = properties.Save(t.Context(), work, work.Metadata.FillExtractedProperties(m.DocumentMetadata{Description: "Late AI description", Sender: "Late AI sender", Tags: []string{"late-ai"}}))
			if scenario != "metadata cleared" {
				if !errors.Is(err, m.ErrStaleJob) {
					t.Fatalf("obsolete AI result published after %s: %v", scenario, err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			var title, description, sender string
			var tags []string
			if err := f.connection.QueryRow(t.Context(), "SELECT title,description,sender,tags FROM documents WHERE account_id=$1 AND id=$2", f.actor.AccountID, doc.ID).Scan(&title, &description, &sender, &tags); err != nil {
				t.Fatal(err)
			}
			if title != "Keep user title" || description != "" || sender != "" || len(tags) != 0 {
				t.Fatalf("concurrent user metadata change overwritten: %q %q %q %v", title, description, sender, tags)
			}
			aiIndependentAssertSearchable(t, f, doc.ID)
		})
	}
}

func TestAISettingsDuringIngestionApplyWhenFollowupIsAccepted(t *testing.T) {
	for _, enable := range []bool{true, false} {
		name := "disable during ingestion"
		if enable {
			name = "enable during ingestion"
		}
		t.Run(name, func(t *testing.T) {
			f := newIngestionFixture(t)
			llmSource(t, f)
			if !enable {
				aiIndependentEnableProperties(t, f)
			}
			doc := f.accept(t, f.actor, strings.Repeat("5", 64), "Settings changed while queued")
			current, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
			if err != nil {
				t.Fatal(err)
			}
			invoiceEnabled := false
			next, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{
				Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision,
				LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: enable, InvoiceEnabled: &invoiceEnabled, Provider: "ollama", Model: "qwen3.5:4b"},
			})
			if err != nil {
				t.Fatal(err)
			}
			if err := f.service.MaintainProcessing(t.Context()); err != nil {
				t.Fatal(err)
			}
			if n := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE document_id=$1", doc.ID); n != 0 {
				t.Fatal("AI was accepted before mandatory ingestion finished")
			}
			aiIndependentReady(t, f, doc, "independent search publication")
			var revision int64
			var status string
			if err := f.connection.QueryRow(t.Context(), "SELECT configuration_revision,status FROM document_ai_jobs WHERE document_id=$1 ORDER BY attempt DESC LIMIT 1", doc.ID).Scan(&revision, &status); err != nil {
				t.Fatal(err)
			}
			wantStatus := "skipped"
			if enable {
				wantStatus = "queued"
			}
			if revision != next.Revision || status != wantStatus {
				t.Fatalf("AI inherited obsolete ingestion settings: revision=%d status=%s; want revision=%d status=%s", revision, status, next.Revision, wantStatus)
			}
			aiIndependentAssertSearchable(t, f, doc.ID)
		})
	}
}

func TestAIMissingHistoryDistinguishesNeverPermittedFromAmbiguousStart(t *testing.T) {
	for _, permitted := range []bool{false, true} {
		name := "never permitted"
		if permitted {
			name = "start result unknown"
		}
		t.Run(name, func(t *testing.T) {
			f := newIngestionFixture(t)
			source := llmSource(t, f)
			aiIndependentEnableProperties(t, f)
			doc := f.accept(t, f.actor, strings.Repeat("6", 64), "Retain ambiguous AI ownership")
			aiIndependentReady(t, f, doc, "independent search publication")
			if !permitted {
				f.exec(t, "UPDATE document_ai_jobs SET next_check_at=clock_timestamp()+interval '1 hour' WHERE document_id=$1", doc.ID)
			}
			leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker")
			if err != nil || (len(leases) == 1) != permitted {
				t.Fatalf("AI delivery permit: %+v %v", leases, err)
			}
			f.exec(t, "UPDATE document_ai_jobs SET next_check_at=clock_timestamp(),lease_expires_at=NULL,delivery_deadline=clock_timestamp()-interval '1 second' WHERE document_id=$1", doc.ID)
			pending, err := source.AIPending(t.Context(), 100)
			if err != nil || len(pending) != 1 || pending[0].RunID != "" || (pending[0].LatestPermitEnd != nil) != permitted {
				t.Fatalf("missing-history fixture ownership: %+v %v", pending, err)
			}
			if err := documentAIService(source).ResolveExecution(t.Context(), pending[0], "", "delivery_timeout", true); err != nil {
				t.Fatal(err)
			}
			open := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE document_id=$1 AND admitted_at IS NOT NULL AND closed_at IS NULL", doc.ID)
			if (open == 1) != permitted {
				t.Fatalf("missing history closure proof: open=%d permitted=%t", open, permitted)
			}
			aiIndependentAssertSearchable(t, f, doc.ID)
		})
	}
}

type aiIndependentPublishedSnapshot struct {
	State, Stage            string
	Generation, OCRRevision int64
	Chunks                  []aiIndependentChunk
}

func aiIndependentPublished(t *testing.T, f *ingestionFixture, id string) aiIndependentPublishedSnapshot {
	t.Helper()
	var result aiIndependentPublishedSnapshot
	err := f.connection.QueryRow(t.Context(), `SELECT p.state,p.stage,p.generation,d.ocr_revision FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2`, f.actor.AccountID, id).Scan(&result.State, &result.Stage, &result.Generation, &result.OCRRevision)
	if err != nil {
		t.Fatal(err)
	}
	rows, err := f.connection.Query(t.Context(), `SELECT position,content,embedding,model_digest FROM document_chunks WHERE account_id=$1 AND document_id=$2 AND generation=$3 ORDER BY position`, f.actor.AccountID, id, result.Generation)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var chunk aiIndependentChunk
		if err := rows.Scan(&chunk.Position, &chunk.Content, &chunk.Vector, &chunk.Digest); err != nil {
			t.Fatal(err)
		}
		result.Chunks = append(result.Chunks, chunk)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return result
}

func aiIndependentAssertSearchable(t *testing.T, f *ingestionFixture, id string) {
	t.Helper()
	configuration, err := f.repository.SearchConfiguration(t.Context(), f.actor)
	if err != nil {
		t.Fatal(err)
	}
	query, err := (m.DocumentSearchInput{Mode: "semantic", Query: "independent search publication", Space: configuration.EmbeddingSpace(), Limit: 20}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	result, err := f.search(t.Context(), f.actor, query, unitVector(0))
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range result.Items {
		if item.Document.ID == id && item.Document.ProcessingState == "ready" {
			return
		}
	}
	t.Fatalf("published document %s is not semantically searchable: %+v", id, result)
}

func aiIndependentReady(t *testing.T, f *ingestionFixture, doc m.Document, text string) m.DocumentJob {
	t.Helper()
	f.exec(t, "UPDATE document_processing SET split_pipeline=true WHERE account_id=$1 AND document_id=$2 AND state='queued'", f.actor.AccountID, doc.ID)
	f.closeTerminal(t)
	leases, err := f.service.Claim(t.Context(), 1, 30*time.Second, "ai-independent-ingestion")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != doc.ID {
		t.Fatalf("admit independent ingestion: %+v %v", leases, err)
	}
	job := leases[0].Job
	if !leases[0].SplitPipeline || job.AIAttempt != 0 {
		t.Fatalf("new ingestion did not retain split ownership: %+v", leases[0])
	}
	if err := f.repository.Acknowledge(t.Context(), leases[0], leases[0].WorkflowID, uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	work, err := f.service.Work(t.Context(), job, "extracting")
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.SaveExtraction(t.Context(), job, work.Revision, text); err != nil {
		t.Fatal(err)
	}
	work, err = f.service.Work(t.Context(), job, "embedding")
	if err != nil || work.Stage != "embedding" {
		t.Fatalf("mandatory ingestion waits for optional work: %+v %v", work, err)
	}
	if err := f.service.SaveEmbeddings(t.Context(), job, work.Revision, work.Configuration.EmbeddingSpace(), []m.DocumentChunk{{Text: text, Vector: unitVector(0)}}); err != nil {
		t.Fatal(err)
	}
	if err := f.service.Publish(t.Context(), job, work.Revision); err != nil {
		t.Fatal(err)
	}
	f.closeTerminal(t)
	return job
}

func TestAIConfigurationChangesPreservePublishedSearchIndex(t *testing.T) {
	f := newIngestionFixture(t)
	llmSource(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("1", 64), "Independent search publication")
	aiIndependentReady(t, f, doc, "independent search publication")
	before := aiIndependentPublished(t, f, doc.ID)
	if before.State != "ready" || before.Stage != "complete" || len(before.Chunks) != 1 {
		t.Fatalf("fixture was not published: %+v", before)
	}
	batchCount := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches`)
	for _, scenario := range []struct {
		name, model string
		enabled     bool
	}{
		{name: "enable AI", model: "qwen3.5:4b", enabled: true},
		{name: "change AI model", model: "qwen3.5:9b", enabled: true},
		{name: "disable AI", model: "qwen3.5:9b", enabled: false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			current, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
			if err != nil {
				t.Fatal(err)
			}
			invoiceEnabled := false
			configuration, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{
				Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision,
				LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: scenario.enabled, InvoiceEnabled: &invoiceEnabled, Provider: "ollama", Model: scenario.model},
			})
			if err != nil {
				t.Fatal(err)
			}
			if configuration.Revision != current.Revision+1 {
				t.Fatalf("AI change did not create a configuration revision: %+v", configuration)
			}
			if err := f.service.MaintainProcessing(t.Context()); err != nil {
				t.Fatal(err)
			}
			after := aiIndependentPublished(t, f, doc.ID)
			if !reflect.DeepEqual(before, after) {
				t.Fatalf("AI settings replaced searchable ingestion: before=%+v after=%+v", before, after)
			}
			if got := issue12Count(t, f, `SELECT count(*) FROM document_reindex_batches`); got != batchCount {
				t.Fatalf("AI-only settings scheduled ingestion reindex: before=%d after=%d", batchCount, got)
			}
			aiIndependentAssertSearchable(t, f, doc.ID)
		})
	}
}

func TestAISettingsEnrollReadyLegacyDocumentsWithoutReingestion(t *testing.T) {
	f := newIngestionFixture(t)
	llmSource(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("7", 64), "Legacy searchable document")
	f.ready(t, doc, "independent search publication", unitVector(0))
	before := aiIndependentPublished(t, f, doc.ID)
	if n := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE document_id=$1", doc.ID); n != 0 {
		t.Fatal("legacy fixture invented separate historical AI work")
	}
	if err := f.service.MaintainProcessing(t.Context()); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE document_id=$1", doc.ID); n != 0 {
		t.Fatal("maintenance replayed legacy AI without a settings change")
	}
	configuration := aiIndependentEnableProperties(t, f)
	if err := f.service.MaintainProcessing(t.Context()); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE document_id=$1 AND configuration_revision=$2 AND status='queued'", doc.ID, configuration.Revision); n != 1 {
		t.Fatalf("actual AI setting change did not enroll legacy document once: %d", n)
	}
	if after := aiIndependentPublished(t, f, doc.ID); !reflect.DeepEqual(before, after) {
		t.Fatalf("legacy AI enrollment replaced search index: before=%+v after=%+v", before, after)
	}
	aiIndependentAssertSearchable(t, f, doc.ID)
}

func TestAISettingsDoNotStrandPreviouslyRequestedIngestionReindex(t *testing.T) {
	f := newIngestionFixture(t)
	llmSource(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("8", 64), "Reindex keeps its ingestion snapshot")
	f.ready(t, doc, "independent search publication", unitVector(0))
	batch := issue12Batch(t, f, f.actor, false)
	if err := f.service.MaintainProcessing(t.Context()); err != nil {
		t.Fatal(err)
	}
	configuration := aiIndependentEnableProperties(t, f)
	job := aiIndependentReady(t, f, doc, "independent search publication reindexed")
	if job.Generation != 2 {
		t.Fatalf("pending ingestion reindex was not admitted after AI-only settings: %+v", job)
	}
	processing, err := f.service.Processing(t.Context(), f.actor, doc.ID)
	if err != nil || processing.State != "ready" || processing.ConfigurationRevision != batch.ConfigurationRevision {
		t.Fatalf("reindex lost its accepted ingestion snapshot: %+v %v", processing, err)
	}
	var aiRevision int64
	if err := f.connection.QueryRow(t.Context(), "SELECT configuration_revision FROM document_ai_jobs WHERE document_id=$1 AND generation=$2 ORDER BY attempt DESC LIMIT 1", doc.ID, job.Generation).Scan(&aiRevision); err != nil {
		t.Fatal(err)
	}
	if aiRevision != configuration.Revision {
		t.Fatalf("follow-up did not use latest independently accepted AI settings: got %d want %d", aiRevision, configuration.Revision)
	}
	f.exec(t, "UPDATE document_reindex_items SET next_check_at=clock_timestamp() WHERE batch_id=$1", batch.ID)
	if err := f.service.MaintainProcessing(t.Context()); err != nil {
		t.Fatal(err)
	}
	finished, err := f.service.Batch(t.Context(), f.actor, false, batch.ID)
	if err != nil || finished.Status != "succeeded" || finished.Succeeded != 1 {
		t.Fatalf("AI-only configuration stranded ingestion batch outcome: %+v %v", finished, err)
	}
	aiIndependentAssertSearchable(t, f, doc.ID)
}

func TestAIMandatorySettingsChangeDoesNotDeliverObsoleteEnabledAI(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("9", 64), "Settings changed before rescheduling")
	f.ready(t, doc, "independent search publication", unitVector(0))
	enabled := aiIndependentEnableProperties(t, f)
	invoiceEnabled := false
	_, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{
		Language: "eng", Segmentation: enabled.Segmentation, ExpectedRevision: &enabled.Revision,
		LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: false, InvoiceEnabled: &invoiceEnabled, Provider: "ollama", Model: "qwen3.5:4b"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.MaintainProcessing(t.Context()); err != nil {
		t.Fatal(err)
	}
	if n := issue12Count(t, f, "SELECT count(*) FROM document_ai_jobs WHERE document_id=$1 AND configuration_revision=$2 AND status IN ('queued','running')", doc.ID, enabled.Revision); n != 0 {
		t.Fatalf("mandatory settings save retained obsolete enabled-AI rescheduling intent: %d", n)
	}
	if leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "ai-independent-worker"); err != nil || len(leases) != 0 {
		t.Fatalf("disabled AI was delivered from obsolete rescheduling revision: %+v %v", leases, err)
	}
}
