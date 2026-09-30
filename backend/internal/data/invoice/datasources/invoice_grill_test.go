package datasources_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestGrillInvoiceEvidenceRejectsAmbiguousGrounding(t *testing.T) {
	for _, scenario := range []struct{ name, text, number, currency string }{
		{"period in invoice identifier", "Invoice No. INV.2026\nSeller: Example Office Ltd\nGrand Total: EUR 19.00", "INV", "EUR"},
		{"amount absent despite matching currency", "Invoice No. INV-A\nSeller: Example Office Ltd\nCurrency: EUR\nGrand Total: 119.00\nVAT accounting currency: USD\nVAT accounting total: 2.10 USD", "INV-A", "USD"},
		{"unsupported numeric script is not absent money", "Invoice No. INV-A\nSeller: Example Office Ltd\nGrand Total: ١٩٫٠٠ EUR", "INV-A", "EUR"},
		{"identifier absent despite matching amount", "Invoice No. INV-AB\nSeller: Example Office Ltd\nGrand Total: eur 19.00", "INV-A", "USD"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			response := independentInvoiceResponse(t, scenario.number, "19.00")
			response = strings.ReplaceAll(response, `"currency":"EUR"`, `"currency":"`+scenario.currency+`"`)
			inference := &independentInvoiceInference{response: response}
			value, err := datasources.NewInvoiceExtractorDataSource(inference).Infer(t.Context(), document.DocumentLLMConfiguration{}, "", scenario.text)
			var processing document.DocumentProcessingError
			if !errors.As(err, &processing) || processing.Code != "invalid_invoice" || value != nil {
				t.Fatalf("ambiguous source must preserve a prior invoice: accepted=%v err=%v", value != nil, err)
			}
		})
	}
}
