package models

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestInvoiceClassificationCoverage(t *testing.T) {
	for _, size := range []int{300, 19999, 20000, 20001, 49999, 50000, 50001, 100000} {
		text := "HEAD" + strings.Repeat("ä", size-len("HEADINVOICE AT TAIL")) + "INVOICE AT TAIL"
		for _, pass := range []int{1, 2} {
			input := SelectInvoiceClassificationInput(text, pass)
			budget := 20000
			if pass == 2 {
				budget = 50000
			}
			if input.InputCharacters != min(size, budget) || (size <= budget && input.Text != text) {
				t.Fatalf("unexpected input coverage for %d characters on pass %d: %d", size, pass, input.InputCharacters)
			}
			if !utf8.ValidString(input.Text) || !strings.HasSuffix(input.Text, "INVOICE AT TAIL") || !strings.Contains(input.Text, "HEAD") || input.SourceCharacters != utf8.RuneCountInString(text) {
				t.Fatalf("lost source coverage: %+v", input)
			}
			c := FinalizeInvoiceClassification(InvoiceClassification{Decision: "not_invoice", Reason: "other_document", Pass: pass, InputCharacters: input.InputCharacters, SourceCharacters: input.SourceCharacters}, "")
			if c.Validate() != nil || (c.Decision == "not_invoice") != (input.InputCharacters == input.SourceCharacters) {
				t.Fatalf("sampled text became a definitive negative: %+v", c)
			}
			if InvoiceClassificationNeedsWiderInput(c) != (pass == 1 && input.InputCharacters < input.SourceCharacters) {
				t.Fatal("unexpected wider pass", c)
			}
		}
	}
	negative := InvoiceClassification{Decision: "not_invoice", Reason: "quotation", Pass: 1, InputCharacters: 100, SourceCharacters: 100}
	if c := FinalizeInvoiceClassification(negative, "ai"); c.Decision != "uncertain" || c.Reason != "prior_invoice" {
		t.Fatal("prior invoice conflict lost", c)
	}
}

func TestInvoiceClassificationRejectsInvalidResults(t *testing.T) {
	for _, c := range []InvoiceClassification{
		{Decision: "invoice", Reason: "quotation", Pass: 1},
		{Decision: "not_invoice", Reason: "invoice", Pass: 1},
		{Decision: "uncertain", Reason: "free text", Pass: 1},
		{Decision: "invoice", Reason: "invoice", Pass: 3},
		{Decision: "invoice", Reason: "invoice", Pass: 1, InputCharacters: 10, SourceCharacters: 9},
	} {
		if c.Validate() == nil {
			t.Fatalf("accepted invalid classification: %+v", c)
		}
	}
	if InvoiceClassificationTextUsable("12 € ...") || !InvoiceClassificationTextUsable(strings.Repeat("字", 20)) {
		t.Fatal("invalid usable-text check")
	}
}
