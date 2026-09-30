package datasources

import (
	"context"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type inferenceFixture struct {
	response      string
	calls         int
	contextLength int
	maxTokens     int
	schema        string
	temperature   float64
	compatibility bool
	thinking      bool
}

func (f *inferenceFixture) Generate(_ context.Context, provider, model, url, key, prompt, schema, text string, maxTokens int, temperature float64, lmStudioCompatibility, thinkingEnabled bool, contextLength ...int) (string, error) {
	f.calls++
	f.schema = schema
	f.temperature = temperature
	f.maxTokens = maxTokens
	f.compatibility = lmStudioCompatibility
	f.thinking = thinkingEnabled
	if len(contextLength) > 0 {
		f.contextLength = contextLength[0]
	}
	return f.response, nil
}

func TestInvoiceInferenceUsesAcceptedPipelineContext(t *testing.T) {
	f := &inferenceFixture{response: `{"isInvoice":false,"invoice":null}`}
	_, err := NewInvoiceExtractorDataSource(f).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "openai", Model: "model", ContextLength: 65536, LMStudioCompatibility: true}, "", "Example invoice")
	if err != nil || f.contextLength != 65536 || f.temperature != 0.2 || f.maxTokens != 50000 || !f.compatibility {
		t.Fatalf("invoice context was lost: %d %v", f.contextLength, err)
	}
}
func TestAIExtractionRequiresInvoiceDecisionAndExactStrings(t *testing.T) {
	for _, scenario := range []struct {
		json           string
		valid, invoice bool
	}{
		{`{"isInvoice":false,"invoice":null}`, true, false},
		{`{"isInvoice":false,"invoice":{}}`, true, false},
		{`{"isInvoice":false,"invoice":{"number":"","currency":"","totalGross":0,"seller":null}}`, true, false},
		{`{"isInvoice":false,"invoice":{"unrelated":"unused model output"}}`, true, false},
		{`{"isInvoice":true,"invoice":{"number":"AI-1","currency":"KWD","seller":{"name":"Supplier"},"totalGross":"1.190"}}`, true, true},
		{`{}`, false, false}, {`{"isInvoice":null,"invoice":null}`, false, false}, {`{"isInvoice":true,"invoice":null}`, false, false},
		{`{"isInvoice":"false","invoice":null}`, false, false},
		{`{"isInvoice":false,"invoice":null} {}`, false, false},
		{`{"isInvoice":false,"invoice":`, false, false},
		{`{"isInvoice":true,"invoice":{}}`, false, false},
		{`{"isInvoice":true}`, false, false},
		{`{"isInvoice":true,"invoice":{"number":"AI-1","currency":"EUR","seller":{"name":"Supplier"},"totalGross":119.00}}`, false, false},
		{`{"isInvoice":true,"invoice":{"number":"AI-1","currency":"ZZZ","seller":{"name":"Supplier"}}}`, false, false},
		{`{"isInvoice":true,"invoice":{"number":"AI-1","currency":"EUR","seller":{"name":"Supplier"},"source":"structured"}}`, false, false},
		{`{"isInvoice":true,"invoice":{"number":"AI-1","currency":"EUR","seller":{"name":"Supplier"},"references":[{"number":"I-0","invoiceId":"fake"}]}}`, false, false},
	} {
		f := &inferenceFixture{response: scenario.json}
		v, err := NewInvoiceExtractorDataSource(f).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "openai", Model: "fixture"}, "key", "Invoice No. AI-1\nSeller: Supplier\nGrand Total: 1.1900 KWD")
		if (err == nil) != scenario.valid || (v != nil && err == nil) != scenario.invoice {
			t.Fatalf("%s: %+v %v", scenario.json, v, err)
		}
		if v != nil && err == nil && (v.Source != "ai" || v.TotalGross != "1.190" || v.ExtractionModel != "fixture") {
			t.Fatalf("wrong provenance: %+v", v)
		}
	}
}

func TestAIExtractionPreservesTaxCurrenciesAndRejectsUnpairedAmounts(t *testing.T) {
	for _, scenario := range []struct {
		name, fields, taxCurrency, taxAmount string
		valid                                bool
	}{
		{"invoice currency only", `"totalTax":"42.28"`, "", "", true},
		{"no accounting tax", `"totalTax":"42.28","vatAccounting":null`, "", "", true},
		{"explicit accounting currency", `"totalTax":"42.28","vatAccounting":{"currency":"USD","amount":"46.50"}`, "USD", "46.50", true},
		{"missing accounting currency", `"totalTax":"42.28","vatAccounting":{"amount":"42.28"}`, "", "", false},
		{"missing accounting amount", `"totalTax":"42.28","vatAccounting":{"currency":"USD"}`, "", "", false},
		{"copied invoice tax", `"totalTax":"42.28","vatAccounting":{"currency":"EUR","amount":"42.28"}`, "", "", false},
		{"invalid accounting currency", `"totalTax":"42.28","vatAccounting":{"currency":"ZZZ","amount":"46.50"}`, "", "", false},
		{"old unpaired field", `"totalTax":"42.28","taxAccountingAmount":"42.28"`, "", "", false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			f := &inferenceFixture{response: `{"isInvoice":true,"invoice":{"number":"TAX-1","currency":"EUR","totalGross":"119.00","seller":{"name":"Supplier"},` + scenario.fields + `}}`}
			v, err := NewInvoiceExtractorDataSource(f).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "ollama", Model: "fixture"}, "", "Invoice No. TAX-1\nSeller: Supplier\nGrand Total: 119.00 EUR\nVAT: 42.28 EUR\nAccounting VAT: 46.50 USD")
			if !scenario.valid {
				if err == nil || v != nil {
					t.Fatal("accepted an accounting amount without a valid accounting currency")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if v == nil || v.Currency != "EUR" || v.TotalTax != "42.28" || v.TaxCurrency != scenario.taxCurrency || v.TaxAccountingAmount != scenario.taxAmount {
				t.Fatalf("lost tax evidence: %+v", v)
			}
		})
	}
}

func TestInvoiceThinkingIsIndependentFromPropertyThinking(t *testing.T) {
	for _, thinking := range []bool{false, true} {
		c := document.DocumentLLMConfiguration{InvoiceThinkingEnabled: thinking, PropertyThinkingEnabled: !thinking}
		f := &inferenceFixture{response: `{"isInvoice":false,"invoice":null}`}
		if _, err := NewInvoiceExtractorDataSource(f).Infer(t.Context(), c, "", "Synthetic invoice"); err != nil || f.thinking != thinking {
			t.Fatalf("invoice thinking lost: %t %v", f.thinking, err)
		}
		f.response = `{"invoice":null}`
		_, _ = NewInvoiceExtractorDataSource(f).InferClassified(t.Context(), c, "", "Synthetic invoice")
		if f.thinking != thinking || f.calls != 2 {
			t.Fatal("classified invoice thinking lost")
		}
	}
}
