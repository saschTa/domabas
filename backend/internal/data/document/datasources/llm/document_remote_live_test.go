//go:build llm_live

package llm

import (
	"context"
	"log/slog"
	"math"
	"os"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestLiveQwenAndEmbeddingShareRuntime(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live Qwen/embedding tests")
	}
	r, err := NewDocumentPropertyRemoteDataSource(endpoint, slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(r.Close)
	for _, name := range []string{"invoice A", "invoice B", "invoice C", "invoice D"} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			ctx, cancel := context.WithTimeout(t.Context(), 4*time.Minute)
			defer cancel()
			text := "Invoice from Example Office to Sample Customer. Invoice date: 2026-09-19. Subject: " + name + ". Office stationery, total EUR 42.00. Payment due in 14 days."
			properties, err := r.Extract(ctx, "ollama", "qwen3.5:4b", "", "", text, false, false)
			if err != nil {
				t.Fatal(err)
			}
			if properties.Description == "" || properties.Sender == "" || properties.DocumentDate != "2026-09-19" {
				t.Fatalf("Qwen must return populated properties and the explicit invoice date: %+v", properties)
			}
			if _, err := (m.DocumentMetadata{Title: name, Description: properties.Description, Tags: properties.Tags, Sender: properties.Sender, Recipients: properties.Recipients, Subject: properties.Subject, DocumentDate: properties.DocumentDate}).Normalize(); err != nil {
				t.Fatalf("Qwen properties cannot be saved: %v", err)
			}
			var embedded struct {
				Embeddings [][]float64 `json:"embeddings"`
			}
			err = r.request(ctx, r.ollama+"/api/embed", "", map[string]any{"model": "nomic-embed-text:v1.5", "input": []string{text}, "keep_alive": "5m"}, &embedded)
			if err != nil {
				t.Fatal(err)
			}
			if len(embedded.Embeddings) != 1 || len(embedded.Embeddings[0]) != 768 {
				t.Fatal("embedding model must remain available while Qwen processes other documents")
			}
			var magnitude float64
			for _, v := range embedded.Embeddings[0] {
				if math.IsNaN(v) || math.IsInf(v, 0) {
					t.Fatal("non-finite embedding")
				}
				magnitude += v * v
			}
			if magnitude == 0 {
				t.Fatal("empty embedding")
			}
		})
	}
}

func TestLiveQwenPostalAddressesProduceValidMetadata(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live Qwen tests")
	}
	remote, err := NewDocumentPropertyRemoteDataSource(endpoint, slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remote.Close)
	text := "Rechnung EXAMPLE-2026-17\nRechnungsdatum: 25.07.2026\nAbsender:\nExample Büro GmbH\nSample Street 1\n10115 Berlin\nDeutschland\nEmpfänger:\nSample Customer AG\nOther Street 2\n20095 Hamburg\nDeutschland\nBeratung: 200,00 EUR\nUmsatzsteuer 19%: 38,00 EUR\nGesamtbetrag: 238,00 EUR"
	properties, err := remote.Extract(t.Context(), "ollama", "qwen3.5:4b", "", "", text, false, false)
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
