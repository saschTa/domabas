package services

import (
	"context"
	"errors"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"strings"
	"testing"
)

type invoiceClassifierFixture struct {
	decision, reason string
	calls            int
	failure          error
}

func (f *invoiceClassifierFixture) Classify(_ context.Context, _ document.DocumentLLMConfiguration, _ string, input m.InvoiceClassificationInput) (m.InvoiceClassification, error) {
	f.calls++
	return m.InvoiceClassification{Decision: f.decision, Reason: f.reason, Pass: input.Pass, InputCharacters: input.InputCharacters, SourceCharacters: input.SourceCharacters}, f.failure
}

func TestInvoiceClassificationRoutesAndCheckpoints(t *testing.T) {
	for _, scenario := range []struct {
		name, decision, reason, text, prior, expected string
		calls, extraction                             int
	}{
		{"positive", "invoice", "invoice", "Invoice with unreadable number and currency", "", "invoice", 1, 1},
		{"negative", "not_invoice", "quotation", "Quotation for a prospective future purchase", "", "not_invoice", 1, 0},
		{"uncertain", "uncertain", "ambiguous", "Document with an ambiguous business purpose", "", "uncertain", 1, 0},
		{"prior preserved", "not_invoice", "other_document", "Career profile for the example candidate", "ai", "uncertain", 1, 0},
		{"poor text", "invoice", "invoice", "01234 ...", "", "uncertain", 0, 0},
		{"empty text", "invoice", "invoice", "", "", "uncertain", 0, 0},
		{"wider pass", "not_invoice", "other_document", strings.Repeat("a", 20001), "", "not_invoice", 2, 0},
		{"uncovered text", "not_invoice", "other_document", strings.Repeat("a", 50001), "", "uncertain", 2, 0},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			job := document.DocumentJob{AIAttempt: 1}
			r := &repositoryFixture{work: m.InvoiceWork{Job: job, ClassifierVersion: 1, MediaType: "application/pdf", Text: scenario.text, ExistingSource: scenario.prior, Configuration: document.DocumentLLMConfiguration{InvoiceEnabled: new(true)}}}
			e := &extractorFixture{}
			classifier := &invoiceClassifierFixture{decision: scenario.decision, reason: scenario.reason}
			s := NewInvoiceService(r, e, e, invoiceTestAuthority{}, classifier)
			if err := s.ExtractInvoice(t.Context(), job); err != nil {
				t.Fatal(err)
			}
			if classifier.calls != scenario.calls || e.inferred != scenario.extraction || r.work.Classification.Decision != scenario.expected || r.saves != 1 {
				t.Fatalf("unexpected route: %+v %+v %+v", classifier, e, r)
			}
			if scenario.extraction == 0 && (!r.savedWork.Skipped || r.savedWork.RemovePreviousAI) {
				t.Fatal("skip could remove a previous invoice")
			}
			checkpoints := r.classificationSaves
			if err := s.ExtractInvoice(t.Context(), job); err != nil {
				t.Fatal(err)
			}
			if classifier.calls != scenario.calls || r.classificationSaves != checkpoints {
				t.Fatal("activity retry repeated completed classification")
			}
		})
	}
}

func TestInvoiceClassificationFailureDoesNotExtractOrCheckpoint(t *testing.T) {
	job := document.DocumentJob{AIAttempt: 1}
	r := &repositoryFixture{work: m.InvoiceWork{Job: job, ClassifierVersion: 1, MediaType: "application/pdf", Text: "Invoice from a concrete business transaction", Configuration: document.DocumentLLMConfiguration{InvoiceEnabled: new(true)}}}
	e := &extractorFixture{}
	failure := document.DocumentProcessingError{Code: "output_limit"}
	c := &invoiceClassifierFixture{failure: failure}
	if err := NewInvoiceService(r, e, e, invoiceTestAuthority{}, c).ExtractInvoice(t.Context(), job); !errors.Is(err, failure) || e.inferred != 0 || r.saves != 0 || r.classificationSaves != 0 {
		t.Fatalf("failed classification reached extraction: %v", err)
	}
}
