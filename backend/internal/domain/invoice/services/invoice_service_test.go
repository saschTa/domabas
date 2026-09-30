package services

import (
	"context"
	"errors"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/invoice/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

type repositoryFixture struct {
	p.InvoiceRepository
	work                m.InvoiceWork
	saves               int
	invoice             *m.Invoice
	classificationSaves int
	savedWork           m.InvoiceWork
}

func (f *repositoryFixture) Work(context.Context, document.DocumentJob) (m.InvoiceWork, error) {
	work := f.work
	if work.Stage == "" {
		work.Stage = "invoicing"
		work.ResumeStage = "embedding"
	}
	return work, nil
}
func (f *repositoryFixture) BeginWork(context.Context, m.InvoiceWork) error { return nil }
func (f *repositoryFixture) Save(_ context.Context, work m.InvoiceWork, v *m.Invoice) error {
	f.saves++
	f.invoice = v
	f.savedWork = work
	return nil
}

func (f *repositoryFixture) SaveClassification(_ context.Context, _ m.InvoiceWork, c m.InvoiceClassification) error {
	f.classificationSaves++
	f.work.Classification = c
	return nil
}

type extractorFixture struct {
	structured, inferred, credentials int
	failure                           error
	credentialRead                    func(context.Context) (string, error)
}

func (f *extractorFixture) Structured(context.Context, []byte) (*m.Invoice, error) {
	f.structured++
	return &m.Invoice{Source: "structured", Number: "I-1", Currency: "EUR", Seller: m.InvoiceParty{Name: "Seller"}}, f.failure
}
func (f *extractorFixture) Infer(context.Context, document.DocumentLLMConfiguration, string, string) (*m.Invoice, error) {
	f.inferred++
	return nil, f.failure
}
func (f *extractorFixture) InferClassified(ctx context.Context, c document.DocumentLLMConfiguration, key, text string) (*m.Invoice, error) {
	return f.Infer(ctx, c, key, text)
}
func (f *extractorFixture) PropertyCredential(ctx context.Context, _ string) (string, error) {
	f.credentials++
	if f.credentialRead != nil {
		return f.credentialRead(ctx)
	}
	return "secret", nil
}

func TestInvoicePreservesCancellationDuringCredentialRead(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	r := &repositoryFixture{work: m.InvoiceWork{MediaType: "application/pdf", Text: "invoice", Configuration: document.DocumentLLMConfiguration{Enabled: true}}}
	e := &extractorFixture{credentialRead: func(context.Context) (string, error) {
		cancel()
		return "", errors.New("credential storage unavailable")
	}}
	if err := NewInvoiceService(r, e, e, invoiceTestAuthority{}, nil).ExtractInvoice(ctx, document.DocumentJob{AIAttempt: 1}); !errors.Is(err, context.Canceled) || e.inferred != 0 || r.saves != 0 {
		t.Fatalf("credential cancellation became an AI failure: %v", err)
	}
}
func TestInvoiceStagePrioritizesStructuredEvidenceAndCheckpoints(t *testing.T) {
	for _, scenario := range []struct {
		name                        string
		work                        m.InvoiceWork
		fail                        bool
		structured, inferred, saves int
	}{
		{name: "completed", work: m.InvoiceWork{Done: true}},
		{name: "structured with AI disabled", work: m.InvoiceWork{XML: []byte("xml")}, structured: 1, saves: 1},
		{name: "PDF inference", work: m.InvoiceWork{MediaType: "application/pdf", Text: "invoice", Configuration: document.DocumentLLMConfiguration{Enabled: true}}, inferred: 1, saves: 1},
		{name: "email inference", work: m.InvoiceWork{MediaType: "message/rfc822", Text: "invoice", Configuration: document.DocumentLLMConfiguration{Enabled: true}}, inferred: 1, saves: 1},
		{name: "disabled", work: m.InvoiceWork{MediaType: "application/pdf", Text: "invoice"}, saves: 1},
		{name: "properties only", work: m.InvoiceWork{MediaType: "application/pdf", Text: "invoice", Configuration: document.DocumentLLMConfiguration{Enabled: true, InvoiceEnabled: new(false)}}, saves: 1},
		{name: "invoices only", work: m.InvoiceWork{MediaType: "application/pdf", Text: "invoice", Configuration: document.DocumentLLMConfiguration{InvoiceEnabled: new(true)}}, inferred: 1, saves: 1},
		{name: "both enabled", work: m.InvoiceWork{MediaType: "application/pdf", Text: "invoice", Configuration: document.DocumentLLMConfiguration{Enabled: true, InvoiceEnabled: new(true)}}, inferred: 1, saves: 1},
		{name: "both disabled preserve structured", work: m.InvoiceWork{XML: []byte("xml"), Configuration: document.DocumentLLMConfiguration{InvoiceEnabled: new(false)}}, structured: 1, saves: 1},
		{name: "malformed structured never falls back", work: m.InvoiceWork{XML: []byte("xml"), MediaType: "application/pdf", Text: "invoice", Configuration: document.DocumentLLMConfiguration{Enabled: true}}, fail: true, structured: 1},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			r := &repositoryFixture{work: scenario.work}
			e := &extractorFixture{}
			if scenario.fail {
				e.failure = document.DocumentProcessingError{Code: "invalid_invoice"}
			}
			err := NewInvoiceService(r, e, e, invoiceTestAuthority{}, nil).ExtractInvoice(t.Context(), document.DocumentJob{})
			if (err != nil) != scenario.fail || r.saves != scenario.saves || e.structured != scenario.structured || e.inferred != scenario.inferred || e.credentials != scenario.inferred {
				t.Fatalf("unexpected pipeline result: %v repository %+v extractor %+v", err, r, e)
			}
		})
	}
}
