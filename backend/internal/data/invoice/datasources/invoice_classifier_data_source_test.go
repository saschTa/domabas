package datasources

import (
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"testing"
)

func TestInvoiceClassifierSmallStrictDecision(t *testing.T) {
	for _, scenario := range []struct {
		output string
		valid  bool
	}{
		{`{"reason":"invoice"}`, true},
		{`{"reason":"quotation"}`, true},
		{`{"reason":"ambiguous"}`, true},
		{`{"reason":"invoice","invoice":{}}`, false},
		{`{"reason":"other_document","reason":"invoice"}`, false},
		{`{"reason":"prior_invoice"}`, false},
		{`{"reason":"incomplete_coverage"}`, false},
		{`{"decision":"not_invoice","reason":"invoice"}`, false},
		{`{"decision":"invoice"}`, false},
		{`{"reason":"invoice"} {}`, false},
		{`{"reason":null}`, false},
		{`{"reason":1}`, false},
		{`{}`, false},
		{`null`, false},
	} {
		f := &inferenceFixture{response: scenario.output}
		input := invoice.SelectInvoiceClassificationInput("Invoice for a concrete transaction", 1)
		value, err := NewInvoiceClassifierDataSource(f).Classify(t.Context(), document.DocumentLLMConfiguration{ContextLength: 65536, LMStudioCompatibility: true}, "", input)
		if (err == nil) != scenario.valid || f.contextLength != 65536 || f.temperature != 0.2 || !f.compatibility || value.InputCharacters != input.InputCharacters {
			t.Fatalf("%s: %+v %v", scenario.output, value, err)
		}
	}
}

func TestClassifiedExtractionCannotSilentlyChangeDecision(t *testing.T) {
	f := &inferenceFixture{response: `{"isInvoice":false,"invoice":null}`}
	_, err := NewInvoiceExtractorDataSource(f).InferClassified(t.Context(), document.DocumentLLMConfiguration{}, "", "Invoice number UNKNOWN. Seller and currency unreadable.")
	if err == nil {
		t.Fatal("extraction silently changed a positive decision")
	}
}

func TestInvoiceClassificationUsesInvoiceThinking(t *testing.T) {
	for _, thinking := range []bool{false, true} {
		f := &inferenceFixture{response: `{"reason":"other_document"}`}
		c := document.DocumentLLMConfiguration{InvoiceThinkingEnabled: thinking, PropertyThinkingEnabled: !thinking}
		_, err := NewInvoiceClassifierDataSource(f).Classify(t.Context(), c, "", invoice.SelectInvoiceClassificationInput("Synthetic ordinary document", 1))
		if err != nil || f.thinking != thinking || f.calls != 1 {
			t.Fatalf("classification thinking lost: %t %v", f.thinking, err)
		}
	}
}
