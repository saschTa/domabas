package datasources_test

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type independentInvoiceInference struct {
	response string
	input    string
}

func (f *independentInvoiceInference) Generate(_ context.Context, _, _, _, _, _, _, text string, _ int, _ float64, _ bool, _ bool, _ ...int) (string, error) {
	f.input = text
	return f.response, nil
}

func independentInvoiceResponse(t *testing.T, number, total string) string {
	t.Helper()
	data, err := json.Marshal(map[string]any{
		"isInvoice": true,
		"invoice": map[string]any{
			"number": number, "currency": "EUR", "seller": map[string]string{"name": "Example Office Ltd"}, "totalGross": total,
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestIndependentInvoiceExtractionRequiresSourceValues(t *testing.T) {
	for _, scenario := range []struct {
		name, text, number, total, outcome string
	}{
		{"career year and fabricated zero", "Career profile\nExample Office Ltd\n2020: project coordinator\nSkills: planning and communication", "2020", "0.00", "invalid"},
		{"contract references and percentage", "Allgemeine Bedingungen\nExample Office Ltd\n1. Rechnungen sind nach Zugang zu bezahlen.\nDie Anpassung beträgt 0,25 Prozent.", "1", "137.50", "invalid"},
		{"generic invoice mention with unrelated fee", "General terms\nExample Office Ltd\n1. Invoices are payable when received.\nAn administrative fee of EUR 137.50 may apply.", "1", "137.50", "invoice"},
		{"malformed positive cannot become negative", "Career profile without financial information", "", "0.00", "invalid"},
		{"identifier must be whole", "Invoice No. EVID-10\nSeller: Example Office Ltd\nGrand Total: EUR 19.00", "EVID-1", "19.00", "invalid"},
		{"amount must be whole", "Invoice No. EVID-1\nSeller: Example Office Ltd\nGrand Total: EUR 119.00", "EVID-1", "19.00", "invalid"},
		{"credit sign cannot disappear", "Credit Note No. CN-1\nSeller: Example Office Ltd\nGrand Total: EUR -19.00", "CN-1", "19.00", "invalid"},
		{"explicit German zero total", "Rechnung Nr. RE-1\nVerkäufer: Example Office Ltd\nGesamtbetrag: 0,00 €", "RE-1", "0.00", "invoice"},
		{"explicit German signed credit", "Gutschrift Nr. CN-1\nVerkäufer: Example Office Ltd\nGesamtbetrag: -1.234,56 EUR", "CN-1", "-1234.56", "invoice"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			inference := &independentInvoiceInference{response: independentInvoiceResponse(t, scenario.number, scenario.total)}
			value, err := datasources.NewInvoiceExtractorDataSource(inference).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "ollama", Model: "fixture"}, "", scenario.text)
			switch scenario.outcome {
			case "invalid":
				var processing document.DocumentProcessingError
				if !errors.As(err, &processing) || processing.Code != "invalid_invoice" || value != nil {
					t.Fatalf("unsupported positive must fail without publishing: %+v %v", value, err)
				}
			case "invoice":
				if err != nil || value == nil || value.Number != scenario.number || value.TotalGross != scenario.total || value.Source != "ai" {
					t.Fatalf("explicit source evidence was lost: %+v %v", value, err)
				}
			}
		})
	}
}

func TestIndependentInvoiceClassificationUsesOnlyModelInputPrefix(t *testing.T) {
	prefix := strings.Repeat("ä", 100000)
	inference := &independentInvoiceInference{response: independentInvoiceResponse(t, "EVID-1", "19.00")}
	value, err := datasources.NewInvoiceExtractorDataSource(inference).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "ollama", Model: "fixture"}, "", prefix+"\nInvoice No. EVID-1\nSeller: Example Office Ltd\nGrand Total: EUR 19.00")
	var processing document.DocumentProcessingError
	if !errors.As(err, &processing) || processing.Code != "invalid_invoice" || value != nil {
		t.Fatalf("source beyond the model input justified a fabricated positive: %+v %v", value, err)
	}
	if inference.input != prefix || utf8.RuneCountInString(inference.input) != 100000 {
		t.Fatalf("inference and evidence did not share the Unicode input bound: %d runes", utf8.RuneCountInString(inference.input))
	}
	grounded := "Invoice No. EVID-1\nSeller: Example Office Ltd\nGrand Total: EUR 19.00\n"
	text := strings.Repeat("ä", 100000-utf8.RuneCountInString(grounded)-1) + "\n" + grounded + "omitted tail"
	value, err = datasources.NewInvoiceExtractorDataSource(inference).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "ollama", Model: "fixture"}, "", text)
	if err != nil || value == nil || utf8.RuneCountInString(inference.input) != 100000 {
		t.Fatalf("grounded evidence inside the bounded input was lost: %+v %v", value, err)
	}
}

func TestIndependentInvoiceExtractionDoesNotGateOnCurrencyWording(t *testing.T) {
	for _, currency := range []string{"₹", "eur"} {
		t.Run(currency, func(t *testing.T) {
			inference := &independentInvoiceInference{response: independentInvoiceResponse(t, "EVID-1", "19.00")}
			value, err := datasources.NewInvoiceExtractorDataSource(inference).Infer(t.Context(), document.DocumentLLMConfiguration{Provider: "ollama", Model: "fixture"}, "", "Invoice No. EVID-1\nSeller: Example Office Ltd\nGrand Total: "+currency+" 19.00")
			if err != nil || value == nil {
				t.Fatalf("currency wording blocked printed values: %+v %v", value, err)
			}
		})
	}
}
