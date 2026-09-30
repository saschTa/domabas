//go:build llm_live

package datasources_test

import (
	"context"
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/llm"
	"github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

type recordedInference struct {
	remote   *llm.DocumentPropertyRemoteDataSource
	response string
}

func (r *recordedInference) Generate(ctx context.Context, provider, model, baseURL, key, prompt, schema, text string, maxTokens int, temperature float64, lmStudioCompatibility, thinkingEnabled bool, contextLength ...int) (string, error) {
	var err error
	r.response, err = r.remote.Generate(ctx, provider, model, baseURL, key, prompt, schema, text, maxTokens, temperature, lmStudioCompatibility, thinkingEnabled, contextLength...)
	return r.response, err
}

func TestLiveQwenClassifiedInvoiceSchema(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live Qwen invoice tests")
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	remote, err := llm.NewDocumentPropertyRemoteDataSource(endpoint, logger)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remote.Close)
	inference := &recordedInference{remote: remote}
	classifier := datasources.NewInvoiceClassifierDataSource(inference, logger)
	extractor := datasources.NewInvoiceExtractorDataSource(inference, logger)
	config := document.DocumentLLMConfiguration{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: 32768}
	for _, scenario := range []struct{ name, text, decision, number string }{
		{"career profile", "Career profile\nExample Candidate\nSoftware engineer, 2019-2026. Education: Computer Science. Skills: Go, SQL and Flutter.", "not_invoice", ""},
		{"invoice without optional dates", "Invoice No. SCHEMA-1\nSeller: Example Supplies Ltd\nCurrency: EUR\nNet Total: 100.00 EUR\nTax Total: 19.00 EUR\nGrand Total: 119.00 EUR", "invoice", "SCHEMA-1"},
		{"German invoice", "Rechnung Nr. SCHEMA-DE-1\nVerkäufer: Beispiel Lieferant GmbH\nWährung: EUR\nNettobetrag: 100,00 EUR\nUmsatzsteuer: 19,00 EUR\nGesamtbetrag: 119,00 EUR", "invoice", "SCHEMA-DE-1"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 6*time.Minute)
			defer cancel()
			classification, err := classifier.Classify(ctx, config, "", invoice.SelectInvoiceClassificationInput(scenario.text, 1))
			if err != nil || classification.Decision != scenario.decision {
				t.Fatalf("classification=%+v error=%v", classification, err)
			}
			if classification.Decision != "invoice" {
				return
			}
			value, err := extractor.InferClassified(ctx, config, "", scenario.text)
			if err != nil || value == nil {
				t.Fatalf("classified extraction failed: %v; synthetic response: %s", err, inference.response)
			}
			if value.Number != scenario.number || value.Currency != "EUR" || value.TotalGross != "119.00" || value.TotalNet != "100.00" || value.TotalTax != "19.00" || value.IssueDate != "" || value.DueDate != "" || value.AmountDue != "" || value.TaxCurrency != "" {
				t.Fatalf("invoice header or optional fields differ: %+v", value)
			}
		})
	}
}

func TestLiveQwenInvoiceTaxCurrencies(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live Qwen invoice tests")
	}
	remote, err := llm.NewDocumentPropertyRemoteDataSource(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remote.Close)
	inference := &recordedInference{remote: remote}
	extractor := datasources.NewInvoiceExtractorDataSource(inference)
	for _, scenario := range []struct {
		name, text, taxCurrency, taxAmount string
	}{
		{
			name: "single currency with multiple VAT rates",
			text: `Invoice No. TAX-2026-001
Seller: Example Office Ltd. Buyer: Sample Customer Ltd.
Invoice date: 2026-09-19. Due date: 2026-10-19. Currency: EUR.
Description | Quantity | Unit price | Net amount | VAT rate | VAT amount
Office supplies | 2 | 10.00 EUR | 20.00 EUR | 19% | 3.80 EUR
Books | 1 | 30.00 EUR | 30.00 EUR | 7% | 2.10 EUR
Net Total: 50.00 EUR
Tax Total: 5.90 EUR
Grand Total: 55.90 EUR`,
		},
		{
			name: "explicit separate VAT accounting currency",
			text: `Invoice No. TAX-2026-001
Seller: Example Office Ltd. Buyer: Sample Customer Ltd.
Invoice date: 2026-09-19. Currency: EUR.
Net Total: 50.00 EUR
Tax Total: 5.90 EUR
Grand Total: 55.90 EUR
VAT accounting currency: USD
Total VAT for accounting and reporting: 6.49 USD`,
			taxCurrency: "USD", taxAmount: "6.49",
		},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			for _, classified := range []bool{false, true} {
				name := "legacy"
				if classified {
					name = "classified"
				}
				t.Run(name, func(t *testing.T) {
					ctx, cancel := context.WithTimeout(t.Context(), 4*time.Minute)
					defer cancel()
					infer := extractor.Infer
					if classified {
						infer = extractor.InferClassified
					}
					v, err := infer(ctx, document.DocumentLLMConfiguration{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: 32768}, "", scenario.text)
					if err != nil {
						t.Fatalf("%v: %s", err, inference.response)
					}
					if v == nil || v.Number != "TAX-2026-001" || v.Currency != "EUR" || v.TotalNet != "50.00" || v.TotalTax != "5.90" || v.TotalGross != "55.90" || v.TaxCurrency != scenario.taxCurrency || v.TaxAccountingAmount != scenario.taxAmount {
						t.Fatalf("incorrect invoice tax evidence: %+v", v)
					}
				})
			}
		})
	}
}

func TestLiveQwenInvoiceSourceClassification(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live Qwen invoice tests")
	}
	remote, err := llm.NewDocumentPropertyRemoteDataSource(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remote.Close)
	inference := &recordedInference{remote: remote}
	extractor := datasources.NewInvoiceExtractorDataSource(inference)
	for _, scenario := range []struct {
		name, text, number, gross string
		invoice                   bool
	}{
		{name: "career profile", text: "Career profile\nExample Candidate\n2019-2022 Software Engineer at Example Systems\n2022-2026 Senior Engineer\nSkills: Go, databases, distributed systems.\nEducation: Computer Science degree."},
		{name: "general contractual invoicing terms", text: "General Terms and Conditions\nExample Supplier Ltd.\n1. These conditions govern future transactions.\n2. Invoices must be paid after receipt.\n3. A late-payment interest rate of 0,25 percent may apply.\nNo individual transaction, invoice identifier or invoice total is stated in these terms."},
		{name: "ordinary invoice", text: "Invoice No. SOURCE-2026-001\nSeller: Example Supplier Ltd.\nBuyer: Example Buyer Ltd.\nInvoice date: 2026-09-21\nCurrency: EUR\nService: Support\nNet Total: 100.00 EUR\nTax Total: 19.00 EUR\nGrand Total: 119.00 EUR\nAmount Due: 119.00 EUR", number: "SOURCE-2026-001", gross: "119.00", invoice: true},
		{name: "German invoice", text: "Rechnung Nr. DE-2026-001\nVerkäufer: Beispiel Lieferant GmbH\nKäufer: Beispiel Kunde GmbH\nRechnungsdatum: 2026-09-21\nWährung: EUR\nLeistung: Beratung\nNettobetrag: 100,00 EUR\nUmsatzsteuer: 19,00 EUR\nGesamtbetrag: 119,00 EUR\nZahlbetrag: 119,00 EUR", number: "DE-2026-001", gross: "119.00", invoice: true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 4*time.Minute)
			defer cancel()
			value, err := extractor.Infer(ctx, document.DocumentLLMConfiguration{Provider: "ollama", Model: "qwen3.5:4b"}, "", scenario.text)
			if err != nil {
				t.Fatalf("%v; synthetic response: %s", err, inference.response)
			}
			if (value != nil) != scenario.invoice {
				t.Fatalf("invoice=%v, expected %v", value != nil, scenario.invoice)
			}
			if value != nil && (value.Number != scenario.number || value.TotalGross != scenario.gross || value.Currency != "EUR") {
				t.Fatalf("wrong extracted values: %+v", value)
			}
		})
	}
}

func TestLiveQwenInvoicePrintedFormats(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live Qwen invoice tests")
	}
	remote, err := llm.NewDocumentPropertyRemoteDataSource(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remote.Close)
	inference := &recordedInference{remote: remote}
	classifier := datasources.NewInvoiceClassifierDataSource(inference)
	extractor := datasources.NewInvoiceExtractorDataSource(inference)
	config := document.DocumentLLMConfiguration{Provider: "ollama", Model: "qwen3.5:4b", ContextLength: 32768}
	text := "Rechnungs-Nr. FORMAT-2026-1 / 16.09.2026\nVerkäufer: Beispiel Lieferant GmbH\nNetto-Summe: 1.000,00 EUR\nMehrwertsteuer: 19 % auf 1.000,00 EUR = 190,00 EUR\nRechnungsendbetrag in EUR 1.190,00"
	ctx, cancel := context.WithTimeout(t.Context(), 6*time.Minute)
	defer cancel()
	classification, err := classifier.Classify(ctx, config, "", invoice.SelectInvoiceClassificationInput(text, 1))
	if err != nil || classification.Decision != "invoice" {
		t.Fatalf("classification=%+v error=%v", classification, err)
	}
	value, err := extractor.InferClassified(ctx, config, "", text)
	if err != nil || value == nil {
		t.Fatalf("classified extraction failed: %v; synthetic response: %s", err, inference.response)
	}
	if value.Number != "FORMAT-2026-1" || value.Currency != "EUR" || value.TotalNet != "1000.00" || value.TotalTax != "190.00" || value.TotalGross != "1190.00" || value.IssueDate != "2026-09-16" {
		t.Fatalf("printed formats were not normalized: %+v", value)
	}
}
