//go:build integration

package repos_test

import (
	"encoding/base64"
	"strings"
	"testing"
	"time"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	paperlesssources "github.com/domabas/domabas/backend/internal/data/paperless/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func aiResourceFixture(t *testing.T) (*ingestionFixture, *sources.DocumentDataSource, m.Document) {
	t.Helper()
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	aiIndependentEnableProperties(t, f)
	doc := f.accept(t, f.actor, strings.Repeat("a", 64), "Resource scheduled AI")
	aiIndependentReady(t, f, doc, "published before optional processing")
	return f, source, doc
}

func TestAIResourceAdmissionDoesNotWaitForUnreservedIngestion(t *testing.T) {
	f, source, doc := aiResourceFixture(t)
	f.accept(t, f.actor, strings.Repeat("b", 64), "Queued ingestion")
	aiIndependentClaim(t, source, doc.ID)
	if count := issue12Count(t, f, `SELECT count(*) FROM scheduler_requests WHERE state='active' AND pipeline='document_ai'`); count != 1 {
		t.Fatalf("active AI reservation: %d", count)
	}
}

func TestAIAndIngestionShareRetainedOllamaCapacity(t *testing.T) {
	f, source, doc := aiResourceFixture(t)
	lease := aiIndependentClaim(t, source, doc.ID)
	queued := f.accept(t, f.actor, strings.Repeat("b", 64), "Ingestion waiting for Ollama")
	for _, terminal := range []bool{false, true} {
		if terminal {
			if err := source.AIFail(t.Context(), lease.Job, "inference_unavailable"); err != nil {
				t.Fatal(err)
			}
		}
		if jobs, err := f.service.Claim(t.Context(), 1, time.Second, "resource-ingestion"); err != nil || len(jobs) != 0 {
			t.Fatalf("unclosed AI released model capacity: %+v %v", jobs, err)
		}
		aiIndependentAssertSearchable(t, f, doc.ID)
	}
	pending, err := source.AIPending(t.Context(), 10)
	if err != nil || len(pending) != 1 {
		t.Fatal(pending, err)
	}
	if err = documentAIService(source).ResolveExecution(t.Context(), pending[0], pending[0].RunID, "processing_incomplete", false); err != nil {
		t.Fatal(err)
	}
	jobs, err := f.service.Claim(t.Context(), 1, time.Second, "resource-ingestion")
	if err != nil || len(jobs) != 1 || jobs[0].Job.DocumentID != queued.ID {
		t.Fatalf("closed AI did not admit waiting ingestion: %+v %v", jobs, err)
	}
}

func TestAIAndPaperlessCompeteOnlyForWorkerCapacity(t *testing.T) {
	for _, workers := range []int{1, 2} {
		t.Run(string(rune('0'+workers)), func(t *testing.T) {
			f, source, doc := aiResourceFixture(t)
			f.exec(t, "UPDATE scheduler_resources SET concurrency_limit=$1 WHERE id='worker'", workers)
			imports, err := paperlesssources.NewPaperlessJobsDataSource(f.source.Database(), base64.StdEncoding.EncodeToString(make([]byte, 32)), "resource-paperless", f.scheduler)
			if err != nil {
				t.Fatal(err)
			}
			id := uuid.NewString()
			f.exec(t, `INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue) VALUES($1,$2,$3,1,'https://paperless.example.test','test-only','resource-paperless')`, id, f.actor.AccountID, f.actor.UserID)
			execution, err := imports.Next(t.Context())
			if err != nil || execution == nil || execution.ID != id {
				t.Fatal(execution, err)
			}
			leases, err := source.AIClaim(t.Context(), 1, time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "resource-ai")
			if err != nil {
				t.Fatal(err)
			}
			if workers == 1 && len(leases) != 0 {
				t.Fatal("AI exceeded shared worker capacity")
			}
			if workers == 2 && (len(leases) != 1 || leases[0].Job.DocumentID != doc.ID) {
				t.Fatalf("Paperless consumed Ollama capacity: %+v", leases)
			}
			if count := issue12Count(t, f, `SELECT count(*) FROM scheduler_request_resources r JOIN scheduler_requests q USING(workflow_id) WHERE q.pipeline='paperless' AND r.resource_id='ollama'`); count != 0 {
				t.Fatal("Paperless acquired model resource")
			}
		})
	}
}

func TestAIInvoiceOnlyUsesAcceptedProviderResource(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	current, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
	if err != nil {
		t.Fatal(err)
	}
	enabled := true
	endpoint := "https://external.example.test/v1"
	accepted, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision, LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: false, InvoiceEnabled: &enabled, Provider: "openai", Model: "invoice-model", BaseURL: endpoint}})
	if err != nil {
		t.Fatal(err)
	}
	doc := f.accept(t, f.actor, strings.Repeat("c", 64), "Invoice provider snapshot")
	aiIndependentReady(t, f, doc, "Invoice total 42 EUR")
	_, err = f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{Language: accepted.Language, Segmentation: accepted.Segmentation, ExpectedRevision: &accepted.Revision, LLMUpdate: &m.DocumentLLMConfigurationUpdate{Enabled: false, InvoiceEnabled: &enabled, Provider: "ollama", Model: "qwen3.5:4b"}})
	if err != nil {
		t.Fatal(err)
	}
	lease := aiIndependentClaim(t, source, doc.ID)
	var resources []string
	if err = f.connection.QueryRow(t.Context(), `SELECT ARRAY(SELECT resource_id FROM scheduler_request_resources WHERE workflow_id=$1 ORDER BY resource_id)`, lease.WorkflowID).Scan(&resources); err != nil {
		t.Fatal(err)
	}
	if len(resources) != 2 || resources[0] != f.scheduler.ResourceID(endpoint) || resources[1] != "worker" {
		t.Fatalf("invoice-only snapshot used wrong resources: %v", resources)
	}
}

func TestAIResourceReservationPreservesDeliveryRetry(t *testing.T) {
	f, source, doc := aiResourceFixture(t)
	leases, err := source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "resource-ai")
	if err != nil || len(leases) != 1 {
		t.Fatal(leases, err)
	}
	first := leases[0]
	f.accept(t, f.actor, strings.Repeat("b", 64), "New ingestion")
	if err := source.AIRelease(t.Context(), first, time.Now().Add(-time.Second)); err != nil {
		t.Fatal(err)
	}
	leases, err = source.AIClaim(t.Context(), 1, 30*time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "resource-ai")
	if err != nil || len(leases) != 1 || leases[0].Job.DocumentID != doc.ID || leases[0].ID != first.ID || leases[0].LeaseToken == first.LeaseToken || !leases[0].DeliveryDeadline.Equal(first.DeliveryDeadline) {
		t.Fatalf("resource contention broke delivery recovery: %+v %v", leases, err)
	}
	if count := issue12Count(t, f, `SELECT count(*) FROM scheduler_requests WHERE state='active' AND pipeline='document_ai'`); count != 1 {
		t.Fatalf("delivery retry duplicated resource reservation: %d", count)
	}
}

func TestAIResourceCandidateScanDiscoversOtherEndpointsAfterBlockedPage(t *testing.T) {
	f := newIngestionFixture(t)
	source := llmSource(t, f)
	f.resourceCapacity(t, 64)
	docs := make([]m.Document, 24)
	for i := range docs {
		docs[i] = f.accept(t, f.actor, strings.Repeat(string(rune('a'+i%6)), 62)+string("0123456789abcdef"[i/16])+string("0123456789abcdef"[i%16]), "Provider scheduling candidate")
		aiIndependentReady(t, f, docs[i], "searchable scheduling fixture")
	}
	configure := func(endpoint string) m.DocumentProcessingConfiguration {
		current, err := f.service.GetProcessingConfiguration(t.Context(), f.actor)
		if err != nil {
			t.Fatal(err)
		}
		invoice := false
		update := m.DocumentLLMConfigurationUpdate{Enabled: endpoint != "", InvoiceEnabled: &invoice, Provider: "ollama", Model: "fixture-model"}
		if endpoint != "" {
			update.Provider = "openai"
			update.BaseURL = endpoint
		}
		configured, err := f.service.SetProcessingConfiguration(t.Context(), f.actor, m.DocumentProcessingConfiguration{Language: current.Language, Segmentation: current.Segmentation, ExpectedRevision: &current.Revision, LLMUpdate: &update})
		if err != nil {
			t.Fatal(err)
		}
		return configured
	}
	enqueue := func(doc m.Document, configuration m.DocumentProcessingConfiguration) {
		if _, err := f.service.RetryAI(t.Context(), f.actor, doc.ID, m.DocumentReindexRequest{RequestID: uuid.NewString(), ConfigurationRevision: configuration.Revision}); err != nil {
			t.Fatal(err)
		}
	}
	first := configure("https://endpoint-a.example.test/v1")
	for _, doc := range docs[:22] {
		enqueue(doc, first)
	}
	second := configure("https://endpoint-b.example.test/v1")
	enqueue(docs[22], second)
	cpu := configure("")
	f.exec(t, `UPDATE document_processing SET invoice_xml=$2 WHERE document_id=$1`, docs[23].ID, []byte("<Invoice/>"))
	enqueue(docs[23], cpu)
	admitted := map[string]bool{}
	for range 6 {
		leases, err := source.AIClaim(t.Context(), 1, time.Second, m.PlanDocumentDelivery(m.DocumentDeliverySettings{UnlimitedInference: true}), "provider-scan")
		if err != nil {
			t.Fatal(err)
		}
		for _, lease := range leases {
			admitted[lease.Job.DocumentID] = true
		}
	}
	if !admitted[docs[22].ID] || !admitted[docs[23].ID] || len(admitted) != 4 {
		t.Fatalf("blocked endpoint hid independent or worker-only AI: %v", admitted)
	}
	if active := issue12Count(t, f, `SELECT count(*) FROM scheduler_requests q JOIN scheduler_request_resources r USING(workflow_id) WHERE q.state='active' AND r.resource_id=$1`, f.scheduler.ResourceID("https://endpoint-a.example.test/v1")); active != 2 {
		t.Fatalf("blocked provider capacity exceeded: %d", active)
	}
}
