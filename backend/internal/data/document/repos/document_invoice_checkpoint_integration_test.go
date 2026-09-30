//go:build integration

package repos_test

import (
	"errors"
	invoicesources "github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	invoicerepos "github.com/domabas/domabas/backend/internal/data/invoice/repos"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	invoiceservices "github.com/domabas/domabas/backend/internal/domain/invoice/services"
	"strings"
	"testing"
)

func TestInvoiceClassificationCheckpointRecoveryAndStaleWrites(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	source := llmSource(t, f)
	configuration, err := f.service.GetProcessingConfiguration(ctx, f.actor)
	if err != nil {
		t.Fatal(err)
	}
	_, err = f.service.SetProcessingConfiguration(ctx, f.actor, document.DocumentProcessingConfiguration{Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision, LLMUpdate: &document.DocumentLLMConfigurationUpdate{Enabled: false, InvoiceEnabled: new(true), Provider: "ollama", Model: "qwen3.5:4b"}})
	if err != nil {
		t.Fatal(err)
	}
	doc := f.accept(t, f.actor, strings.Repeat("b", 64), "Invoice checkpoint")
	aiIndependentReady(t, f, doc, strings.Repeat("readable business document ", 50))
	job := aiIndependentClaim(t, source, doc.ID).Job
	data := invoicesources.NewInvoiceDataSource(f.source.Database())
	service := invoiceservices.NewInvoiceService(invoicerepos.NewInvoiceRepository(data), nil, nil, f.authority, nil)
	work, err := service.Work(ctx, job)
	if err != nil || work.ClassifierVersion != 1 {
		t.Fatalf("new attempt missing classifier: %+v %v", work, err)
	}
	first := invoice.InvoiceClassification{Decision: "uncertain", Reason: "incomplete_coverage", Pass: 1, InputCharacters: 600, SourceCharacters: len(work.Text)}
	if err := data.SaveClassification(ctx, work, first); err != nil {
		t.Fatal(err)
	}
	recovered, err := service.Work(ctx, job)
	if err != nil || recovered.Classification != first {
		t.Fatalf("checkpoint recovery: %+v %v", recovered, err)
	}
	if err := data.SaveClassification(ctx, work, first); !errors.Is(err, document.ErrStaleJob) {
		t.Fatalf("stale pass overwritten: %v", err)
	}
	second := invoice.InvoiceClassification{Decision: "not_invoice", Reason: "other_document", Pass: 2, InputCharacters: len(work.Text), SourceCharacters: len(work.Text)}
	if err := data.SaveClassification(ctx, recovered, second); err != nil {
		t.Fatal(err)
	}
	current, err := f.service.Processing(ctx, f.actor, doc.ID)
	if err != nil || current.AI == nil || current.AI.InvoiceDecision != "not_invoice" || current.AI.InvoiceClassificationPass != 2 {
		t.Fatalf("current classification missing: %+v %v", current, err)
	}
	history, err := f.service.JobHistory(ctx, f.actor, current.AI.JobID)
	if err != nil || history.InvoiceDecision != "not_invoice" || history.InvoiceSourceCharacters != len(work.Text) {
		t.Fatalf("history classification missing: %+v %v", history, err)
	}
	recovered, err = service.Work(ctx, job)
	if err != nil {
		t.Fatal(err)
	}
	recovered.Skipped = true
	if err := service.Save(ctx, recovered, nil); err != nil {
		t.Fatal(err)
	}
	if err := data.SaveClassification(ctx, work, first); !errors.Is(err, document.ErrStaleJob) {
		t.Fatalf("completed invoice step accepted checkpoint: %v", err)
	}
	done, err := service.Work(ctx, job)
	if err != nil || !done.Done {
		t.Fatalf("invoice skip not complete: %+v %v", done, err)
	}
}
