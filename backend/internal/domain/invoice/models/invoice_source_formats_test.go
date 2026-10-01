package models

import (
	"strings"
	"testing"
)

func TestInvoiceEvidenceOCRNumberFormats(t *testing.T) {
	for _, test := range []struct {
		name, source, value string
		accepted            bool
	}{
		{"ordinary grouping", "Total EUR 1 234,56", "1234.56", true},
		{"thin grouping", "1\u2009234,56", "1234.56", true},
		{"multiple groups", "Total 12 345 678,90 EUR", "12345678.90", true},
		{"decimal spacing", "1234 , 56", "1234.56", true},
		{"punctuation spacing", "1 . 234 , 56", "1234.56", true},
		{"attached currency suffix", "1234,56EUR", "1234.56", true},
		{"attached currency prefix", "EUR1234,56", "1234.56", true},
		{"attached unit", "5kg", "5", true},
		{"accounting negative", "(1 234,56)", "-1234.56", true},
		{"trailing negative", "1234,56-", "-1234.56", true},
		{"spaced sign", "−\u00a01234,56", "-1234.56", true},
		{"typographic sign", "–1234,56", "-1234.56", true},
		{"typographic trailing sign", "1234,56–", "-1234.56", true},
		{"partial spaced number", "1 234,56", "234.56", false},
		{"lost parentheses sign", "(1234,56)", "1234.56", false},
		{"lost trailing sign", "1234,56-", "1234.56", false},
		{"separated subtraction keeps first value", "119.00 - 19.00", "119.00", true},
		{"separated subtraction keeps following sign", "119.00 - 19.00", "-19.00", true},
		{"label separator is not a negative sign", "119.00 - VAT", "-119.00", false},
		{"table cells", "2 100.00 200.00", "2100", false},
		{"table cells remain available", "2 100.00 200.00", "100", true},
		{"tab separated cells", "2\t100.00", "2100", false},
		{"column separated cells", "2  100.00", "2100", false},
		{"line separated cells", "2\n100.00", "2100", false},
		{"attached arbitrary letters", "ITEM1234,56", "1234.56", false},
		{"currency inside identifier", "ITEM-EUR1234,56", "1234.56", false},
		{"unit prefix of identifier", "5kgABC", "5", false},
		{"date component", "16. 09. 2026", "16", false},
		{"named date component", "16 September 2026", "16", false},
		{"malformed grouping", "12,34.56", "1234.56", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			v := Invoice{Number: "INV-1", Currency: "EUR", TotalGross: test.value}
			accepted, err := (InvoiceEvidencePolicy{}).Accept("INV-1\n"+test.source, v)
			if accepted != test.accepted || (err == nil) != test.accepted {
				t.Fatalf("accepted=%v error=%v", accepted, err)
			}
		})
	}
}

func TestInvoiceEvidenceOCRDateFormats(t *testing.T) {
	for _, test := range []struct {
		name, source, value string
		accepted            bool
	}{
		{"dotted day first", "01.10.2026", "2026-10-01", true},
		{"dotted order is not swapped", "01.10.2026", "2026-01-10", false},
		{"separator whitespace", "16. 09. 2026", "2026-09-16", true},
		{"line wrap", "2026 /\n09 / 16", "2026-09-16", true},
		{"typographic date separator", "2026–09–16", "2026-09-16", true},
		{"English month", "16 September 2026", "2026-09-16", true},
		{"English month first", "September 16, 2026", "2026-09-16", true},
		{"German month", "1. März 2026", "2026-03-01", true},
		{"German month alternative", "1. Maerz 2026", "2026-03-01", true},
		{"abbreviated month", "16. Sept. 2026", "2026-09-16", true},
		{"hyphenated named date", "16-Sep-2026", "2026-09-16", true},
		{"typographic named date", "16–Sep–2026", "2026-09-16", true},
		{"slash day first evidence", "16/09/2026\n01/10/2026", "2026-10-01", true},
		{"slash month first evidence", "09/16/2026\n10/01/2026", "2026-10-01", true},
		{"slash order conflict", "16/09/2026\n09/16/2026\n01/10/2026", "2026-10-01", false},
		{"slash ambiguous", "01/10/2026", "2026-10-01", false},
		{"short year established", "16.09.2026\n01.10.26", "2026-10-01", true},
		{"short year absent century", "16.09.26", "2026-09-16", false},
		{"short year conflicting centuries", "16.09.1926\n16.09.2026\n01.10.26", "2026-10-01", false},
		{"invalid named date", "30 February 2026", "2026-02-28", false},
		{"invalid numeric date", "30.02.2026", "2026-02-28", false},
		{"wrong month", "16 September 2026", "2026-10-16", false},
		{"partial year", "16 September 20260", "2026-09-16", false},
		{"date inside identifier", "REF-2026-09-16-123", "2026-09-16", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			accepted, err := (InvoiceEvidencePolicy{}).Accept("INV-1\n"+test.source, Invoice{Number: "INV-1", IssueDate: test.value})
			if accepted != test.accepted || (err == nil) != test.accepted {
				t.Fatalf("accepted=%v error=%v", accepted, err)
			}
		})
	}
}

func BenchmarkInvoiceEvidenceLargeOCR(b *testing.B) {
	source := "INV-1\n" + strings.Repeat("Total EUR 1 234,56\n", 5000)
	value := Invoice{Number: "INV-1", Currency: "EUR", TotalGross: "1234.56"}
	for b.Loop() {
		if accepted, err := (InvoiceEvidencePolicy{}).Accept(source, value); !accepted || err != nil {
			b.Fatal(err)
		}
	}
}

func TestInvoiceEvidenceOCRIdentifierFormats(t *testing.T) {
	for _, test := range []struct {
		name, source, value string
		accepted            bool
	}{
		{"spaced separator", "INV - 001", "INV-001", true},
		{"line wrap", "INV-\n001", "INV-001", true},
		{"Unicode line separator", "INV\u2028-\u2028001", "INV-001", true},
		{"nonbreaking hyphen", "INV\u2011001", "INV-001", true},
		{"en dash", "INV–001", "INV-001", true},
		{"spaced slash", "INV / 2026 / 001", "INV/2026/001", true},
		{"spaced period", "INV . 001", "INV.001", true},
		{"abbreviation boundary", "Nr.INV-001", "INV-001", true},
		{"alphanumeric OCR gap", "INV 001", "INV001", true},
		{"alphanumeric printed gap", "INV001", "INV 001", true},
		{"literal regex symbols", "A+[001]", "A+[001]", true},
		{"Unicode identifier", "ÄB - 001", "ÄB-001", true},
		{"leading zeros matter", "INV-001", "INV-1", false},
		{"prefix", "XINV-001", "INV-001", false},
		{"suffix", "INV-001X", "INV-001", false},
		{"slash suffix", "INV-001/2", "INV-001", false},
		{"spaced slash suffix", "INV - 001 / 2", "INV-001", false},
		{"spaced hyphen suffix", "INV - 001 - A", "INV-001", false},
		{"dot suffix", "INV-001.2", "INV-001", false},
		{"regex is literal", "AAAA001", "A+[001]", false},
		{"changed identifier", "INV-002", "INV-001", false},
		{"unrelated digits", "12 34", "1234", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			accepted, err := (InvoiceEvidencePolicy{}).Accept(test.source, Invoice{Number: test.value})
			if accepted != test.accepted || (err == nil) != test.accepted {
				t.Fatalf("accepted=%v error=%v", accepted, err)
			}
		})
	}
}
