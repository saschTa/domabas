//go:build llm_live

package llm

import (
	"log/slog"
	"os"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestLiveProviderPostalAddressesProduceValidMetadata(t *testing.T) {
	endpoint, model := os.Getenv("LM_STUDIO_BASE_URL"), os.Getenv("LM_STUDIO_MODEL")
	if endpoint == "" || model == "" {
		t.Fatal("LM_STUDIO_BASE_URL and LM_STUDIO_MODEL are required for live inference tests")
	}
	remote := NewDocumentPropertyRemoteDataSource(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	t.Cleanup(remote.Close)
	text := "Rechnung EXAMPLE-2026-17\nRechnungsdatum: 25.07.2026\nAbsender:\nExample Büro GmbH\nSample Street 1\n10115 Berlin\nDeutschland\nEmpfänger:\nSample Customer AG\nOther Street 2\n20095 Hamburg\nDeutschland\nBeratung: 200,00 EUR\nUmsatzsteuer 19%: 38,00 EUR\nGesamtbetrag: 238,00 EUR"
	properties, err := remote.Extract(t.Context(), "openai", model, endpoint, os.Getenv("LM_STUDIO_API_KEY"), text, true, false)
	if err != nil {
		t.Fatal(err)
	}
	if properties.Sender == "" || len(properties.Recipients) == 0 || properties.DocumentDate != "2026-07-25" {
		t.Fatal("missing invoice properties", properties)
	}
	if _, err := (m.DocumentMetadata{Title: "Postal address invoice", Description: properties.Description, Tags: properties.Tags, Sender: properties.Sender, Recipients: properties.Recipients, Subject: properties.Subject, DocumentDate: properties.DocumentDate}).Normalize(); err != nil {
		t.Fatalf("postal address properties cannot be saved: %v", err)
	}
}
