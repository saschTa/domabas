package datasources

import (
	"encoding/json"
	"testing"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestInvoiceSourceValuesIgnoreLabels(t *testing.T) {
	for _, scenario := range []struct {
		name, text, number, currency, gross, due string
		accepted                                 bool
		failed                                   bool
	}{
		{name: "ordinary invoice", text: "Invoice No. INV-1\nSupplier\nGrand Total: 119.00 EUR", number: "INV-1", currency: "EUR", gross: "119.00", accepted: true},
		{name: "German grouped amount", text: "Rechnung Nr. INV-1\nSupplier\nGesamtbetrag: 1.234,56 €", number: "INV-1", currency: "EUR", gross: "1234.56", accepted: true},
		{name: "English grouped amount", text: "Invoice No. INV-1\nSupplier\nGrand Total: EUR 1,234.56", number: "INV-1", currency: "EUR", gross: "1234.56", accepted: true},
		{name: "Unicode grouping", text: "Rechnung Nr. INV-1\nSupplier\nGesamtbetrag: 1\u202f234,56 EUR", number: "INV-1", currency: "EUR", gross: "1234.56", accepted: true},
		{name: "printed zero", text: "Invoice No. INV-1\nSupplier\nGrand Total: 0.00 EUR", number: "INV-1", currency: "EUR", gross: "0", accepted: true},
		{name: "negative credit", text: "Gutschrift Nr. INV-1\nSupplier\nGesamtbetrag: −119,00 EUR", number: "INV-1", currency: "EUR", gross: "-119.00", accepted: true},
		{name: "due after payment", text: "Invoice No. INV-1\nSupplier\nGrand Total: 119.00 EUR\nAmount due: 19.00 EUR", number: "INV-1", currency: "EUR", gross: "119.00", due: "19.00", accepted: true},
		{name: "due only", text: "Invoice No. INV-1\nSupplier\nAmount due: 19.00 EUR", number: "INV-1", currency: "EUR", due: "19.00", accepted: true},
		{name: "profile", text: "Supplier\nCareer 2019 to 2024\nSoftware engineering", number: "2019", currency: "EUR", gross: "0", failed: true},
		{name: "generic contract", text: "Supplier\n1. Invoices must be paid on receipt. Interest rate 0,25 percent.", number: "1", currency: "EUR", gross: "137.50", failed: true},
		{name: "identifier role belongs to model", text: "Supplier\n1. Invoices must be paid on receipt. Fee: 137.50 EUR", number: "1", currency: "EUR", gross: "137.50", accepted: true},
		{name: "tax role belongs to model", text: "Invoice No. INV-1\nSupplier\nTotal Tax: 119.00 EUR", number: "INV-1", currency: "EUR", gross: "119", accepted: true},
		{name: "item role belongs to model", text: "Invoice No. INV-1\nSupplier\nService: 119.00 EUR", number: "INV-1", currency: "EUR", gross: "119", accepted: true},
		{name: "partial number", text: "Invoice No. INV-10\nSupplier\nGrand Total: 119.00 EUR", number: "INV-1", currency: "EUR", gross: "119", failed: true},
		{name: "partial amount", text: "Invoice No. INV-1\nSupplier\nGrand Total: 119.00 EUR", number: "INV-1", currency: "EUR", gross: "19", failed: true},
		{name: "wrong sign", text: "Invoice No. INV-1\nSupplier\nGrand Total: -119.00 EUR", number: "INV-1", currency: "EUR", gross: "119", failed: true},
		{name: "currency role belongs to model", text: "Invoice No. INV-1\nSupplier\nCurrency: EUR\nGrand Total: 119.00 USD", number: "INV-1", currency: "EUR", gross: "119", accepted: true},
		{name: "bare dollar", text: "Invoice No. INV-1\nSupplier\nGrand Total: $119.00", number: "INV-1", currency: "USD", gross: "119", accepted: true},
		{name: "ambiguous grouping", text: "Invoice No. INV-1\nSupplier\nGrand Total: 1.190 EUR", number: "INV-1", currency: "EUR", gross: "1190", failed: true},
		{name: "empty total", text: "Invoice No. INV-1\nSupplier\nTax Total: 19.00 EUR", number: "INV-1", currency: "EUR", accepted: true},
		{name: "due role belongs to model", text: "Invoice No. INV-1\nSupplier\nGrand Total: 119.00 EUR\nAmount due: 19.00 EUR", number: "INV-1", currency: "EUR", gross: "19.00", due: "119.00", accepted: true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			payload := map[string]any{"isInvoice": true, "invoice": map[string]any{"number": scenario.number, "currency": scenario.currency, "seller": map[string]string{"name": "Supplier"}, "totalGross": scenario.gross, "amountDue": scenario.due}}
			data, err := json.Marshal(payload)
			if err != nil {
				t.Fatal(err)
			}
			invoice, err := NewInvoiceExtractorDataSource(&inferenceFixture{response: string(data)}).Infer(t.Context(), document.DocumentLLMConfiguration{}, "", scenario.text)
			if (invoice != nil) != scenario.accepted || (err != nil) != scenario.failed {
				t.Fatalf("accepted=%v error=%v", invoice != nil, err)
			}
		})
	}
}
