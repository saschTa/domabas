package datasources

import (
	"encoding/json"
	"strings"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestInvoiceRequestSchemasRequireEveryFactAndAllowNull(t *testing.T) {
	const nested = `{"invoice":{"number":null,"typeCode":null,"issueDate":null,"dueDate":null,"currency":null,"totalNet":null,"totalTax":null,"totalGross":null,"amountDue":null,"paidAmount":null,"roundingAmount":null,"seller":{"name":null,"taxId":null,"registrationId":null,"address":null,"country":null,"email":null},"buyer":{"name":null,"taxId":null,"registrationId":null,"address":null,"country":null,"email":null},"lines":[{"id":null,"description":null,"quantity":null,"unitCode":null,"unitPrice":null,"netAmount":null,"taxCategory":null,"taxRate":null}],"taxes":[{"category":null,"rate":null,"taxableAmount":null,"taxAmount":null,"exemptionReason":null}],"allowances":[{"charge":null,"reason":null,"amount":null,"taxCategory":null,"taxRate":null}],"references":[{"number":null,"issueDate":null}],"payment":{"meansCode":null,"reference":null,"iban":null,"bic":null,"terms":null},"notes":[],"vatAccounting":{"currency":null,"amount":null}}}`
	for name, schema := range map[string]string{"classified": invoiceExtractionSchema, "legacy": invoiceSchema} {
		t.Run(name, func(t *testing.T) {
			response := nested
			if name == "legacy" {
				response = strings.Replace(response, `{"invoice":`, `{"isInvoice":true,"invoice":`, 1)
			}
			if !invoiceSchemaValid(t, schema, response) {
				t.Fatal("required invoice facts must permit honest nulls")
			}
			var payload map[string]any
			if err := json.Unmarshal([]byte(response), &payload); err != nil {
				t.Fatal(err)
			}
			var checkRequired func(any)
			checkRequired = func(value any) {
				switch value := value.(type) {
				case map[string]any:
					for key, child := range value {
						delete(value, key)
						data, err := json.Marshal(payload)
						if err != nil {
							t.Fatal(err)
						}
						if invoiceSchemaValid(t, schema, string(data)) {
							t.Errorf("schema allows omission of %s", key)
						}
						value[key] = child
						checkRequired(child)
					}
				case []any:
					for _, child := range value {
						checkRequired(child)
					}
				}
			}
			checkRequired(payload)
			for _, field := range []string{"seller", "buyer", "lines", "taxes", "allowances", "references", "payment", "notes", "vatAccounting"} {
				payload["invoice"].(map[string]any)[field] = nil
			}
			data, err := json.Marshal(payload)
			if err != nil || !invoiceSchemaValid(t, schema, string(data)) {
				t.Fatal("unknown objects and collections must permit null", err)
			}
		})
	}
}

func TestInvoiceUnknownEssentialFactsRemainInvalid(t *testing.T) {
	for _, field := range []string{"number", "currency", "seller", "seller.name"} {
		t.Run(field, func(t *testing.T) {
			var payload map[string]any
			if err := json.Unmarshal([]byte(invoiceSchemaCompleteResponse), &payload); err != nil {
				t.Fatal(err)
			}
			invoice := payload["invoice"].(map[string]any)
			if field == "seller.name" {
				invoice["seller"].(map[string]any)["name"] = nil
			} else {
				invoice[field] = nil
			}
			data, err := json.Marshal(payload)
			if err != nil || !invoiceSchemaValid(t, invoiceExtractionSchema, string(data)) {
				t.Fatal("model must be able to report an unknown essential fact", err)
			}
			inference := &inferenceFixture{response: string(data)}
			value, err := NewInvoiceExtractorDataSource(inference).InferClassified(t.Context(), document.DocumentLLMConfiguration{}, "", invoiceSchemaTestSource)
			if err == nil || value != nil {
				t.Fatal("unknown essential facts must not create a usable invoice")
			}
		})
	}
}

func TestInvoiceNullableSchemaStillRejectsMalformedFacts(t *testing.T) {
	for _, response := range []string{
		`{"invoice":null}`,
		`{}`,
		`null`,
		strings.Replace(invoiceSchemaCompleteResponse, `"number":"INV-1"`, `"number":""`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"name":"Supplier"`, `"name":""`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"currency":"EUR"`, `"currency":"eur"`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"totalGross":"119.00"`, `"totalGross":119`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"dueDate":""`, `"dueDate":"tomorrow"`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"dueDate":""`, `"dueDate":"2026-13-01"`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"vatAccounting":null`, `"vatAccounting":{"currency":"usd","amount":"2.00"}`, 1),
		strings.Replace(invoiceSchemaCompleteResponse, `"typeCode":null`, `"typeCode":null,"inventedField":null`, 1),
	} {
		if invoiceSchemaValid(t, invoiceExtractionSchema, response) {
			t.Fatalf("nullable schema accepted malformed output: %s", response)
		}
	}
}

func TestInvoiceUnknownFactsStayEmptyAndPrintedZeroIsPreserved(t *testing.T) {
	response := strings.NewReplacer(`"issueDate":""`, `"issueDate":null`, `"dueDate":""`, `"dueDate":null`, `"totalNet":"100.00"`, `"totalNet":null`, `"totalTax":"19.00"`, `"totalTax":"0.00"`, `"totalGross":"119.00"`, `"totalGross":null`).Replace(invoiceSchemaCompleteResponse)
	if !invoiceSchemaValid(t, invoiceExtractionSchema, response) {
		t.Fatal("unknown optional facts and printed zero must be schema-valid")
	}
	inference := &inferenceFixture{response: response}
	value, err := NewInvoiceExtractorDataSource(inference).InferClassified(t.Context(), document.DocumentLLMConfiguration{}, "", "Invoice INV-1\nSeller: Supplier\nCurrency: EUR\nVAT: 0.00 EUR")
	if err != nil || value == nil {
		t.Fatal("unknown optional facts must not fail extraction", err)
	}
	if value.IssueDate != "" || value.DueDate != "" || value.TotalNet != "" || value.TotalGross != "" || value.AmountDue != "" || value.PaidAmount != "" || value.TotalTax != "0.00" {
		t.Fatalf("null became a fabricated fact or zero was lost: %+v", value)
	}
}
