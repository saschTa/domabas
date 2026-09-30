package models

import "testing"

func TestInvoiceEvidencePreservesStructuredSources(t *testing.T) {
	for _, test := range []struct {
		existing, incoming string
		replace            bool
	}{{"structured", "ai", false}, {"structured", "structured", true}, {"ai", "structured", true}, {"ai", "ai", true}, {"", "ai", true}} {
		if got := InvoiceEvidenceCanReplace(test.existing, test.incoming); got != test.replace {
			t.Fatal(test, got)
		}
	}
}
