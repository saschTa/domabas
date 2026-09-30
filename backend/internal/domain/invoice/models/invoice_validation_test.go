package models

import (
	"strings"
	"testing"
)

func TestInvoiceSearchBoundsUnicodeAndRejectsInvalidInput(t *testing.T) {
	for _, text := range []string{"", "  ", "INV-2026-001", strings.Repeat("東", 200)} {
		if err := (InvoiceQuery{Limit: 20, Text: text}).Validate(); err != nil {
			t.Fatalf("valid query %q rejected: %v", text, err)
		}
	}
	for _, text := range []string{strings.Repeat("東", 201), "hidden\x00text", string([]byte{255})} {
		if (InvoiceQuery{Limit: 20, Text: text}).Validate() == nil {
			t.Fatalf("invalid search accepted: %q", text)
		}
	}
}

func TestDecimalAmountsNeverAcceptFloatNotationOrGrouping(t *testing.T) {
	for _, v := range []string{"", "0", "-1.2300", "999999999999999999999999.000000000001", "1.190", "123"} {
		if !Decimal(v) {
			t.Errorf("rejected %q", v)
		}
	}
	for _, v := range []string{"1e3", "NaN", "Infinity", "1,000.00", "1.2345678901234", "+1", "01.00", " 1.00", "9999999999999999999999999"} {
		if Decimal(v) {
			t.Errorf("accepted %q", v)
		}
	}
}
func TestInvoiceRequiresEvidenceAndCurrency(t *testing.T) {
	v := Invoice{Source: "ai", Number: "I-1", Currency: "EUR", Seller: InvoiceParty{Name: "Supplier"}}
	if err := v.Validate(); err != nil {
		t.Fatal(err)
	}
	v.Currency = "€"
	if v.Validate() == nil {
		t.Fatal("accepted a symbol as currency")
	}
	v.Currency = "EUR"
	v.TaxAccountingAmount = "5.00"
	if v.Validate() == nil {
		t.Fatal("accounting tax requires its own currency")
	}
}

func TestInvoiceFilterValidation(t *testing.T) {
	for _, q := range []InvoiceQuery{
		{Limit: 20, Sort: "due_asc", DueFrom: "2026-01-01", DueTo: "2026-12-31"},
		{Limit: 20, Sort: "seller_desc", Seller: strings.Repeat("😀", 4000)},
		{Limit: 20, Currency: "EUR", TotalMin: "999999999999999999999999.000000000001", TotalMax: "999999999999999999999999.000000000002"},
		{Limit: 20, Currency: "KWD", TotalMin: "-12.123", TotalMax: "0"},
	} {
		if err := q.Validate(); err != nil {
			t.Fatalf("valid filter rejected: %v", err)
		}
	}
	for _, q := range []InvoiceQuery{
		{Limit: 20, Sort: "unknown"}, {Limit: 20, DueFrom: "2026-02-30"},
		{Limit: 20, IssueFrom: "2026-12-01", IssueTo: "2026-01-01"},
		{Limit: 20, CreatedFrom: "2026-01-01T00:00:00Z"},
		{Limit: 20, TotalMin: "1"}, {Limit: 20, Currency: "USD", TotalMin: "1e3"},
		{Limit: 20, Currency: "EUR", TotalMin: "999999999999999999999999.000000000002", TotalMax: "999999999999999999999999.000000000001"},
		{Limit: 20, Seller: strings.Repeat("😀", 4001)}, {Limit: 20, Buyer: "bad\x00name"},
	} {
		if q.Validate() == nil {
			t.Fatalf("invalid filters accepted: %+v", q)
		}
	}
	for _, field := range []string{"number", "seller", "buyer", "currency", "typeCode", "format", "paymentMeansCode"} {
		if err := (InvoiceFilterValueQuery{Limit: 20, Field: field, Text: "Acme"}).Validate(); err != nil {
			t.Fatal(err)
		}
	}
	for _, q := range []InvoiceFilterValueQuery{{Limit: 20, Field: "unknown"}, {Limit: 51, Field: "seller"}, {Limit: 20, Field: "seller", Text: strings.Repeat("東", 201)}} {
		if q.Validate() == nil {
			t.Fatal("invalid facet accepted", q)
		}
	}
}
