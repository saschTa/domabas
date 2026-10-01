package datasources

import (
	"encoding/json"
	"strings"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestInvoiceOCRFormatsForEveryGroundedField(t *testing.T) {
	for _, scenario := range []struct {
		field, fields, source string
	}{
		{"number", `{"number":"INV-001"}`, "Nr.INV – 001"},
		{"line identifier", `{"lines":[{"id":"ITEM/001"}]}`, "ITEM / 001"},
		{"reference identifier", `{"references":[{"number":"REF-001"}]}`, "REF-\n001"},
		{"issue date", `{"issueDate":"2026-10-01"}`, "01. 10. 2026"},
		{"due date", `{"dueDate":"2026-10-01"}`, "1. Oktober 2026"},
		{"reference date", `{"references":[{"number":"REF-001","issueDate":"2026-10-01"}]}`, "REF - 001\nOctober 1, 2026"},
		{"net", `{"totalNet":"1234.56"}`, "Total EUR 1 234,56"},
		{"tax", `{"totalTax":"1234.56"}`, "1 . 234 , 56EUR"},
		{"gross", `{"totalGross":"1234.56"}`, "Total EUR 1 234,56"},
		{"amount due", `{"amountDue":"1234.56"}`, "EUR1234,56"},
		{"paid", `{"paidAmount":"1234.56"}`, "1234,56EUR"},
		{"rounding", `{"roundingAmount":"-0.01"}`, "0,01-"},
		{"accounting tax", `{"vatAccounting":{"currency":"GBP","amount":"1234.56"}}`, "1234,56GBP"},
		{"quantity", `{"lines":[{"quantity":"5"}]}`, "5kg"},
		{"unit price", `{"lines":[{"unitPrice":"1234.56"}]}`, "Total EUR 1 234,56"},
		{"line net", `{"lines":[{"netAmount":"1234.56"}]}`, "Total EUR 1 234,56"},
		{"line rate", `{"lines":[{"taxRate":"19.5"}]}`, "19 , 5%"},
		{"tax rate", `{"taxes":[{"rate":"19.5"}]}`, "19 , 5%"},
		{"tax base", `{"taxes":[{"taxableAmount":"1234.56"}]}`, "Total EUR 1 234,56"},
		{"tax amount", `{"taxes":[{"taxAmount":"1234.56"}]}`, "Total EUR 1 234,56"},
		{"allowance amount", `{"allowances":[{"amount":"1234.56"}]}`, "Total EUR 1 234,56"},
		{"allowance rate", `{"allowances":[{"taxRate":"19.5"}]}`, "19 , 5%"},
	} {
		t.Run(scenario.field, func(t *testing.T) {
			for _, classified := range []bool{false, true} {
				fields := map[string]any{"number": "INV-1", "currency": "EUR", "seller": map[string]any{"name": "Supplier"}}
				if err := json.Unmarshal([]byte(scenario.fields), &fields); err != nil {
					t.Fatal(err)
				}
				response := map[string]any{"invoice": fields}
				if !classified {
					response["isInvoice"] = true
				}
				data, err := json.Marshal(response)
				if err != nil {
					t.Fatal(err)
				}
				inference := &inferenceFixture{response: string(data)}
				extractor := NewInvoiceExtractorDataSource(inference)
				infer := extractor.Infer
				if classified {
					infer = extractor.InferClassified
				}
				for _, supported := range []bool{true, false} {
					text := "Invoice INV-1\nSupplier\n"
					if supported {
						text += scenario.source
					}
					value, err := infer(t.Context(), document.DocumentLLMConfiguration{}, "", text)
					if (err == nil && value != nil) != supported {
						t.Fatalf("classified=%v supported=%v: value=%+v error=%v", classified, supported, value, err)
					}
					if !invoiceSchemaValid(t, inference.schema, string(data)) {
						t.Fatal("schema rejects the supported field format")
					}
				}
			}
		})
	}
}

func TestInvoiceOCRMatchingKeepsPrefixLimit(t *testing.T) {
	response := `{"invoice":{"number":"INV-1","currency":"EUR","seller":{"name":"Supplier"},"totalGross":"1234.56"}}`
	source := "Invoice INV-1\nSupplier\n" + strings.Repeat(" ", 100000) + "Total EUR 1 234,56"
	value, err := NewInvoiceExtractorDataSource(&inferenceFixture{response: response}).InferClassified(t.Context(), document.DocumentLLMConfiguration{}, "", source)
	if value != nil || err == nil {
		t.Fatal("evidence outside the inference input was accepted")
	}
}
