//go:build integration

package repos_test

import (
	invoiceservices "github.com/domabas/domabas/backend/internal/domain/invoice/services"
	"reflect"
	"strings"
	"testing"

	documentrepos "github.com/domabas/domabas/backend/internal/data/document/repos"
	invoicesources "github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	invoicerepos "github.com/domabas/domabas/backend/internal/data/invoice/repos"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	fixtures "github.com/domabas/domabas/backend/tests/fixtures/invoices"
	"github.com/google/uuid"
)

func TestIndependentInvoiceClassificationPreservesSourceAndDocument(t *testing.T) {
	for _, pipeline := range []string{"independent", "retained combined"} {
		for _, scenario := range []struct {
			name, source string
			replace      bool
		}{
			{"negative handles prior AI", "ai", false},
			{"negative preserves structured", "structured", false},
			{"positive AI preserves structured", "structured", true},
		} {
			t.Run(pipeline+"/"+scenario.name, func(t *testing.T) {
				f := newIngestionFixture(t)
				ctx := t.Context()
				source := llmSource(t, f)
				configuration, err := f.service.GetProcessingConfiguration(ctx, f.actor)
				if err != nil {
					t.Fatal(err)
				}
				configuration, err = f.service.SetProcessingConfiguration(ctx, f.actor, document.DocumentProcessingConfiguration{
					Language: configuration.Language, Segmentation: configuration.Segmentation, ExpectedRevision: &configuration.Revision,
					LLMUpdate: &document.DocumentLLMConfigurationUpdate{Enabled: false, InvoiceEnabled: new(true), Provider: "ollama", Model: "qwen3.5:4b"},
				})
				if err != nil {
					t.Fatal(err)
				}
				invoices := invoiceservices.NewInvoiceService(invoicerepos.NewInvoiceRepository(invoicesources.NewInvoiceDataSource(f.source.Database())), nil, nil, f.authority, nil)
				doc := f.accept(t, f.actor, strings.Repeat("a", 64), "User document title")
				job := document.DocumentJob{AccountID: f.actor.AccountID, DocumentID: doc.ID, Generation: 1}
				if pipeline == "independent" {
					aiIndependentReady(t, f, doc, "independent search publication and original OCR")
					job = aiIndependentClaim(t, source, doc.ID).Job
				} else {
					f.admit(t, job)
					work, err := f.service.Work(ctx, job, "extracting")
					if err != nil {
						t.Fatal(err)
					}
					if err := f.service.SaveExtraction(ctx, job, work.Revision, "original OCR"); err != nil {
						t.Fatal(err)
					}
				}
				work, err := invoices.Work(ctx, job)
				if err != nil {
					t.Fatal(err)
				}
				initial, err := invoicesources.ParseXML(ctx, fixtures.CII)
				if err != nil {
					t.Fatal(err)
				}
				if scenario.source == "structured" {
					work.XML = fixtures.CII
				} else {
					initial.Source, initial.Format, initial.Profile, initial.ExtractionModel = "ai", "ai", "", "fixture"
				}
				if err := invoices.Save(ctx, work, initial); err != nil {
					t.Fatal(err)
				}
				before, err := invoices.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20})
				if err != nil || len(before.Items) != 1 {
					t.Fatalf("prepare prior invoice: %+v %v", before, err)
				}
				if pipeline == "independent" {
					properties := documentrepos.NewDocumentPropertyRepository(source)
					propertyWork, err := properties.Work(ctx, job)
					if err != nil {
						t.Fatal(err)
					}
					propertyWork.NextStage = "complete"
					if err := properties.Save(ctx, propertyWork, propertyWork.Metadata); err != nil {
						t.Fatal(err)
					}
					if err := documentAIService(source).Complete(ctx, job); err != nil {
						t.Fatal(err)
					}
					pending, err := source.AIPending(ctx, 20)
					if err != nil || len(pending) != 1 {
						t.Fatalf("close seeded AI execution: %+v %v", pending, err)
					}
					if err := documentAIService(source).ResolveExecution(ctx, pending[0], pending[0].RunID, "processing_incomplete", false); err != nil {
						t.Fatal(err)
					}
					if _, err := f.service.RetryAI(ctx, f.actor, doc.ID, document.DocumentReindexRequest{RequestID: uuid.NewString(), ConfigurationRevision: configuration.Revision}); err != nil {
						t.Fatal(err)
					}
					job = aiIndependentClaim(t, source, doc.ID).Job
				} else {
					f.exec(t, "UPDATE document_processing SET invoice_completed_generation=NULL,stage='invoicing',invoice_next_stage='embedding' WHERE document_id=$1", doc.ID)
				}
				work, err = invoices.Work(ctx, job)
				if err != nil {
					t.Fatal(err)
				}
				var published aiIndependentPublishedSnapshot
				if pipeline == "independent" {
					published = aiIndependentPublished(t, f, doc.ID)
				}
				ocr, err := f.service.OCR(ctx, f.actor, doc.ID)
				if err != nil {
					t.Fatal(err)
				}
				var replacement *invoice.Invoice
				if scenario.replace {
					replacement = &invoice.Invoice{Source: "ai", Format: "ai", ExtractionModel: "fixture", Number: "FABRICATED", Currency: "EUR", TotalGross: "1.00", Seller: invoice.InvoiceParty{Name: "Different seller"}, Notes: []string{"Replacement note"}}
				}
				if err := invoices.Save(ctx, work, replacement); err != nil {
					t.Fatal(err)
				}
				checkpoint, err := invoices.Work(ctx, job)
				if err != nil || !checkpoint.Done {
					t.Fatalf("source preservation did not checkpoint invoice work: %+v %v", checkpoint, err)
				}
				after, err := invoices.List(ctx, f.actor, invoice.InvoiceQuery{Limit: 20})
				if err != nil {
					t.Fatal(err)
				}
				if scenario.source == "ai" && pipeline == "retained combined" {
					if len(after.Items) != 0 {
						t.Fatalf("negative classification retained fabricated AI record: %+v", after)
					}
				} else if !reflect.DeepEqual(before, after) {
					t.Fatalf("AI changed structured invoice or its children: before=%+v after=%+v", before, after)
				}
				if pipeline == "independent" {
					current := aiIndependentPublished(t, f, doc.ID)
					if !reflect.DeepEqual(published, current) {
						t.Fatalf("classification changed ingestion or index: before=%+v after=%+v", published, current)
					}
				} else {
					var generation int64
					if err := f.connection.QueryRow(ctx, "SELECT generation FROM document_processing WHERE document_id=$1", doc.ID).Scan(&generation); err != nil || generation != job.Generation {
						t.Fatalf("classification changed retained ingestion generation: %d %v", generation, err)
					}
				}
				currentOCR, err := f.service.OCR(ctx, f.actor, doc.ID)
				if err != nil || !reflect.DeepEqual(ocr, currentOCR) {
					t.Fatalf("classification changed OCR: before=%+v after=%+v err=%v", ocr, currentOCR, err)
				}
				if pipeline == "independent" {
					aiIndependentAssertSearchable(t, f, doc.ID)
				}
			})
		}
	}
}
