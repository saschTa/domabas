package datasources

import (
	"encoding/json"
	"strings"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/santhosh-tekuri/jsonschema/v6"
)

const invoiceSchemaTestResponse = `{"invoice":{"number":"INV-1","issueDate":"","dueDate":"","currency":"EUR","seller":{"name":"Supplier"},"totalNet":"100.00","totalTax":"19.00","totalGross":"119.00","vatAccounting":null}}`
const invoiceSchemaTestSource = "Invoice No. INV-1\nSupplier\nGrand Total: 119.00 EUR\nNet: 100.00\nVAT: 19.00\n29.02.2024"

func TestClassifiedInvoiceSchemaRejectsUnusableResponses(t *testing.T) {
	for _, scenario := range []struct {
		name, response string
		valid          bool
	}{
		{"valid header", invoiceSchemaTestResponse, true},
		{"optional buyer has no name", strings.Replace(invoiceSchemaTestResponse, `"vatAccounting":null`, `"vatAccounting":null,"buyer":{}`, 1), true},
		{"unknown dates empty", invoiceSchemaTestResponse, true},
		{"leap date", strings.Replace(invoiceSchemaTestResponse, `"issueDate":""`, `"issueDate":"2024-02-29"`, 1), true},
		{"null invoice", `{"invoice":null}`, false},
		{"missing invoice", `{}`, false},
		{"null envelope", `null`, false},
		{"trailing JSON", invoiceSchemaTestResponse + ` {}`, false},
		{"redundant decision", strings.Replace(invoiceSchemaTestResponse, `{"invoice":`, `{"isInvoice":true,"invoice":`, 1), false},
		{"negative decision", `{"isInvoice":false,"invoice":null}`, false},
		{"empty number", strings.Replace(invoiceSchemaTestResponse, `"number":"INV-1"`, `"number":""`, 1), false},
		{"missing seller name", strings.Replace(invoiceSchemaTestResponse, `"seller":{"name":"Supplier"}`, `"seller":{}`, 1), false},
		{"empty seller name", strings.Replace(invoiceSchemaTestResponse, `"name":"Supplier"`, `"name":""`, 1), false},
		{"lowercase currency", strings.Replace(invoiceSchemaTestResponse, `"currency":"EUR"`, `"currency":"eur"`, 1), false},
		{"relative date", strings.Replace(invoiceSchemaTestResponse, `"dueDate":""`, `"dueDate":"tomorrow"`, 1), false},
		{"invalid month", strings.Replace(invoiceSchemaTestResponse, `"dueDate":""`, `"dueDate":"2026-13-01"`, 1), false},
		{"reference date placeholder", strings.Replace(invoiceSchemaTestResponse, `"vatAccounting":null`, `"vatAccounting":null,"references":[{"number":"INV-0","issueDate":"unknown"}]`, 1), false},
		{"numeric money", strings.Replace(invoiceSchemaTestResponse, `"totalGross":"119.00"`, `"totalGross":119`, 1), false},
		{"lowercase accounting currency", strings.Replace(invoiceSchemaTestResponse, `"vatAccounting":null`, `"vatAccounting":{"currency":"usd","amount":"2.00"}`, 1), false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			inference := &inferenceFixture{response: scenario.response}
			value, err := NewInvoiceExtractorDataSource(inference).InferClassified(t.Context(), document.DocumentLLMConfiguration{}, "", invoiceSchemaTestSource)
			if inference.temperature != 0.2 {
				t.Fatalf("extraction temperature: %v", inference.temperature)
			}
			if valid := invoiceSchemaValid(t, inference.schema, scenario.response); valid != scenario.valid {
				t.Fatalf("request schema accepted=%t; expected %t", valid, scenario.valid)
			}
			if valid := err == nil && value != nil; valid != scenario.valid {
				t.Fatalf("adapter accepted=%t; error=%v", valid, err)
			}
		})
	}
}

func TestInvoiceSchemaRetainsLegacyNegativeAndPositive(t *testing.T) {
	for _, response := range []string{`{"isInvoice":false,"invoice":null}`, strings.Replace(invoiceSchemaTestResponse, `{"invoice":`, `{"isInvoice":true,"invoice":`, 1)} {
		inference := &inferenceFixture{response: response}
		_, err := NewInvoiceExtractorDataSource(inference).Infer(t.Context(), document.DocumentLLMConfiguration{}, "", invoiceSchemaTestSource)
		if err != nil || !invoiceSchemaValid(t, inference.schema, response) {
			t.Fatalf("legacy response rejected: %v", err)
		}
	}
}

func TestInvoiceSchemaKeepsCalendarAndSourceValidation(t *testing.T) {
	for _, scenario := range []struct{ name, response, source string }{
		{"impossible calendar date", strings.Replace(invoiceSchemaTestResponse, `"dueDate":""`, `"dueDate":"2026-02-30"`, 1), invoiceSchemaTestSource},
		{"invented total", strings.Replace(invoiceSchemaTestResponse, `"totalGross":"119.00"`, `"totalGross":"120.00"`, 1), invoiceSchemaTestSource},
		{"invented date", strings.Replace(invoiceSchemaTestResponse, `"issueDate":""`, `"issueDate":"2026-09-16"`, 1), invoiceSchemaTestSource},
		{"ordinary VAT copied into accounting VAT", strings.Replace(invoiceSchemaTestResponse, `"vatAccounting":null`, `"vatAccounting":{"currency":"EUR","amount":"19.00"}`, 1), invoiceSchemaTestSource},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			inference := &inferenceFixture{response: scenario.response}
			value, err := NewInvoiceExtractorDataSource(inference).InferClassified(t.Context(), document.DocumentLLMConfiguration{}, "", scenario.source)
			if !invoiceSchemaValid(t, inference.schema, scenario.response) || err == nil || value != nil {
				t.Fatalf("schema validity must not bypass evidence/calendar checks: %v", err)
			}
		})
	}
}

func TestInvoiceClassifierSchemaHasOneUnambiguousLabel(t *testing.T) {
	for _, scenario := range []struct{ reason, decision string }{
		{"invoice", "invoice"}, {"credit_note", "invoice"},
		{"quotation", "not_invoice"}, {"order", "not_invoice"}, {"delivery_note", "not_invoice"},
		{"bank_statement", "not_invoice"}, {"forwarding_email", "not_invoice"}, {"other_document", "not_invoice"},
		{"insufficient_text", "uncertain"}, {"mixed_document", "uncertain"}, {"ambiguous", "uncertain"},
	} {
		t.Run(scenario.reason, func(t *testing.T) {
			response := `{"reason":"` + scenario.reason + `"}`
			inference := &inferenceFixture{response: response}
			input := invoice.SelectInvoiceClassificationInput(invoiceSchemaTestSource, 1)
			value, err := NewInvoiceClassifierDataSource(inference).Classify(t.Context(), document.DocumentLLMConfiguration{}, "", input)
			if !invoiceSchemaValid(t, inference.schema, response) || err != nil || value.Decision != scenario.decision || value.Reason != scenario.reason || value.InputCharacters != input.InputCharacters || value.Pass != 1 {
				t.Fatalf("classification mismatch: %+v error=%v", value, err)
			}
		})
	}
	for _, response := range []string{`{"decision":"not_invoice","reason":"invoice"}`, `{"reason":"prior_invoice"}`, `{"reason":"incomplete_coverage"}`, `{"reason":"unknown"}`, `{}`} {
		if invoiceSchemaValid(t, invoiceDetectionSchema, response) {
			t.Fatalf("schema permits unsupported classification: %s", response)
		}
	}
}

func invoiceSchemaValid(t *testing.T, schema, response string) bool {
	t.Helper()
	var definition, value any
	if err := json.Unmarshal([]byte(schema), &definition); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(response), &value); err != nil {
		return false
	}
	compiler := jsonschema.NewCompiler()
	const location = "https://domabas.invalid/invoice-test.schema.json"
	if err := compiler.AddResource(location, definition); err != nil {
		t.Fatal(err)
	}
	compiled, err := compiler.Compile(location)
	if err != nil {
		t.Fatal(err)
	}
	return compiled.Validate(value) == nil
}
