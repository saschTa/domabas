package models

import "testing"

func TestInvoiceEvidenceMatchesValuesWithoutLabels(t *testing.T) {
	v := Invoice{Number: "SYN-42", Currency: "EUR", Seller: InvoiceParty{Name: "Model-selected seller"}, TotalNet: "1058.74", TotalTax: "201.16", TotalGross: "1259.90", IssueDate: "2026-09-16"}
	for _, source := range []string{
		"Rechnungs-Nr. SYN-42 / 16.09.2026\nNetto-Summe: 1.058,74 EUR\nMehrwertsteuer: 201,16 EUR\nRechnungsendbetrag in EUR 1.259,90",
		"SYN-42\n2026-09-16\n1058.74\n201.16\n1259.90",
		"請求 SYN-42\n09/16/2026\n1,058.74\n201.16\n1,259.90",
	} {
		accepted, err := (InvoiceEvidencePolicy{}).Accept(source, v)
		if !accepted || err != nil {
			t.Fatalf("printed facts rejected: %v", err)
		}
	}
}

func TestInvoiceEvidenceChecksCompleteNumbersAndSigns(t *testing.T) {
	for _, test := range []struct {
		name, source, value string
		accepted            bool
	}{
		{"decimal comma", "1.234,56", "1234.56", true},
		{"decimal point", "1,234.56", "1234.56", true},
		{"nonbreaking grouping", "1\u00a0234,56", "1234.56", true},
		{"narrow grouping", "1\u202f234,56", "1234.56", true},
		{"apostrophe grouping", "1’234.56", "1234.56", true},
		{"integer grouping", "1,234,567", "1234567", true},
		{"exact large decimal", "999999999999999999.123456", "999999999999999999.123456", true},
		{"precision preserved", "999999999999999999.123456", "999999999999999999.123457", false},
		{"zero", "0,00", "0", true},
		{"fraction without leading zero", ".50", "0.50", true},
		{"comma fraction without leading zero", ",50", "0.50", true},
		{"fraction is not integer", ".50", "50", false},
		{"trailing zeroes", "00119.0000", "119", true},
		{"negative credit", "−119,00", "-119.00", true},
		{"spaced negative credit", "− 119,00", "-119.00", true},
		{"explicit plus", "+119.00", "119.00", true},
		{"lost negative sign", "-119,00", "119.00", false},
		{"lost spaced negative sign", "- 119,00", "119.00", false},
		{"invented negative sign", "119,00", "-119.00", false},
		{"multiple signs", "+-119,00", "-119.00", false},
		{"partial integer", "119.00", "19", false},
		{"partial fraction", "119.19", "19", false},
		{"identifier digits", "ITEM-119", "119", false},
		{"date digits", "2026-09-16", "2026", false},
		{"slash date digits", "2026/09/19", "19", false},
		{"dot date digits", "19.09.2026", "19", false},
		{"date inside identifier", "REF-2026-09-16-123", "-123", false},
		{"malformed grouping", "12,34.56", "1234.56", false},
		{"ambiguous grouping", "1.234", "1234", false},
		{"ambiguous fraction", "1.234", "1.234", false},
		{"comma convention", "19,00 1.234", "1234", true},
		{"dot convention", "19.00 1.234", "1.234", true},
		{"conflicting conventions", "19.00 19,00 1.234", "1234", false},
		{"three decimal fraction", "1.2340", "1.234", true},
		{"table values stay separate", "2 100.00 200.00", "100", true},
		{"table values never concatenate", "2 100.00 200.00", "2100", false},
		{"missing value", "119.00", "120", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			accepted, err := (InvoiceEvidencePolicy{}).Accept("INV-1\n"+test.source, Invoice{Number: "INV-1", TotalGross: test.value})
			if accepted != test.accepted || (err == nil) != test.accepted {
				t.Fatalf("accepted=%v error=%v", accepted, err)
			}
		})
	}
}

func TestInvoiceEvidenceMatchesCompleteDates(t *testing.T) {
	for _, test := range []struct {
		source, value string
		accepted      bool
	}{
		{"16.09.2026", "2026-09-16", true},
		{"16/9/2026", "2026-09-16", true},
		{"09/16/2026", "2026-09-16", true},
		{"2026-09-16", "2026-09-16", true},
		{"2026/9/16", "2026-09-16", true},
		{"29.02.2024", "2024-02-29", true},
		{"09.09.2026", "2026-09-09", true},
		{"03/04/2026", "2026-04-03", false},
		{"03/04/2026", "2026-03-04", false},
		{"29.02.2026", "2026-02-28", false},
		{"16.09/2026", "2026-09-16", false},
		{"2026 09 16", "2026-09-16", false},
		{"REF-2026-09-16", "2026-09-16", false},
		{"2026-09-160", "2026-09-16", false},
		{"2026-09-16", "2026-09-17", false},
	} {
		t.Run(test.source+"/"+test.value, func(t *testing.T) {
			accepted, err := (InvoiceEvidencePolicy{}).Accept("INV-1\n"+test.source, Invoice{Number: "INV-1", IssueDate: test.value})
			if accepted != test.accepted || (err == nil) != test.accepted {
				t.Fatalf("accepted=%v error=%v", accepted, err)
			}
		})
	}
}

func TestInvoiceEvidenceRejectsUnprintedChildAndHeaderValues(t *testing.T) {
	source := "INV-1 REF-1\n2026-09-16\n119.00 100.00 19.00 2 50.00 0.00"
	for _, test := range []struct {
		name   string
		change func(*Invoice)
	}{
		{"net", func(v *Invoice) { v.TotalNet = "120" }},
		{"tax", func(v *Invoice) { v.TotalTax = "20" }},
		{"due", func(v *Invoice) { v.AmountDue = "120" }},
		{"paid", func(v *Invoice) { v.PaidAmount = "120" }},
		{"rounding", func(v *Invoice) { v.RoundingAmount = "0.01" }},
		{"accounting tax", func(v *Invoice) { v.TaxAccountingAmount = "20" }},
		{"due date", func(v *Invoice) { v.DueDate = "2026-10-16" }},
		{"line id", func(v *Invoice) { v.Lines[0].ID = "3" }},
		{"quantity", func(v *Invoice) { v.Lines[0].Quantity = "3" }},
		{"unit price", func(v *Invoice) { v.Lines[0].UnitPrice = "51" }},
		{"line net", func(v *Invoice) { v.Lines[0].NetAmount = "120" }},
		{"line rate", func(v *Invoice) { v.Lines[0].TaxRate = "20" }},
		{"tax rate", func(v *Invoice) { v.Taxes[0].Rate = "20" }},
		{"tax base", func(v *Invoice) { v.Taxes[0].TaxableAmount = "120" }},
		{"tax amount", func(v *Invoice) { v.Taxes[0].TaxAmount = "20" }},
		{"allowance", func(v *Invoice) { v.Allowances[0].Amount = "3" }},
		{"allowance rate", func(v *Invoice) { v.Allowances[0].TaxRate = "20" }},
		{"reference", func(v *Invoice) { v.References[0].Number = "REF-2" }},
		{"reference date", func(v *Invoice) { v.References[0].IssueDate = "2026-09-17" }},
	} {
		t.Run(test.name, func(t *testing.T) {
			v := Invoice{Number: "INV-1", TotalGross: "119", Lines: []InvoiceLine{{ID: "2", Quantity: "2", UnitPrice: "50", NetAmount: "100", TaxRate: "19"}}, Taxes: []InvoiceTax{{Rate: "19", TaxableAmount: "100", TaxAmount: "19"}}, Allowances: []InvoiceAllowance{{Amount: "0", TaxRate: "19"}}, References: []InvoiceReference{{Number: "REF-1", IssueDate: "2026-09-16"}}}
			if accepted, err := (InvoiceEvidencePolicy{}).Accept(source, v); !accepted || err != nil {
				t.Fatalf("printed baseline rejected: %v", err)
			}
			test.change(&v)
			if accepted, err := (InvoiceEvidencePolicy{}).Accept(source, v); accepted || err == nil {
				t.Fatal("unprinted value accepted")
			}
		})
	}
}

func TestInvoiceEvidenceMatchesWholeIdentifiers(t *testing.T) {
	for _, source := range []string{"INV-10", "XINV-1", "INV-1/2", "INV-1.2", "INV-1.A"} {
		if accepted, err := (InvoiceEvidencePolicy{}).Accept(source, Invoice{Number: "INV-1"}); accepted || err == nil {
			t.Fatalf("partial identifier accepted in %q", source)
		}
	}
	if accepted, err := (InvoiceEvidencePolicy{}).Accept("INV-1", Invoice{Number: "INV-1"}); !accepted || err != nil {
		t.Fatalf("unknown optional amounts rejected: %v", err)
	}
}
