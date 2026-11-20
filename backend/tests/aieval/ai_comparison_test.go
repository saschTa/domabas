//go:build ai_eval

package aieval_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"testing"
	"time"

	chatprovider "github.com/domabas/domabas/backend/internal/data/chat/datasources/provider"
	chatdata "github.com/domabas/domabas/backend/internal/data/chat/models"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/llm"
	"github.com/domabas/domabas/backend/internal/data/invoice/datasources"
	chat "github.com/domabas/domabas/backend/internal/domain/chat/models"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	invoice "github.com/domabas/domabas/backend/internal/domain/invoice/models"
)

func TestAIComparison(t *testing.T) {
	endpoint, model, mode := os.Getenv("AI_EVAL_ENDPOINT"), os.Getenv("AI_EVAL_MODEL"), os.Getenv("AI_EVAL_THINKING")
	if endpoint == "" || model == "" || (mode != "on" && mode != "off") {
		t.Fatal("Use task evaluate:ai with an explicit endpoint and model")
	}
	key := os.Getenv("LM_STUDIO_API_KEY")
	remote := llm.NewDocumentPropertyRemoteDataSource(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	defer remote.Close()
	classifier := datasources.NewInvoiceClassifierDataSource(remote)
	config := document.DocumentLLMConfiguration{Provider: "openai", BaseURL: endpoint, Model: model, LMStudioCompatibility: true, InvoiceThinkingEnabled: mode == "on"}
	invoiceText := "Invoice No. EVAL-2026-001\nSeller: Example Supplies Ltd.\nBuyer: Sample Buyer Ltd.\nCurrency: EUR\nNet Total: 100.00 EUR\nTax Total: 19.00 EUR\nGrand Total: 119.00 EUR\nAmount due: 119.00 EUR"
	for _, tc := range []struct{ name, text, decision string }{
		{"invoice", invoiceText, "invoice"},
		{"quotation", "Quotation Q-2026-001. Example Supplies Ltd. Proposed service EUR 119.00. This is an offer, valid for thirty days. Please accept to place an order.", "not_invoice"},
		{"career profile", "Career profile. Example Candidate. Software engineer from 2019 to 2026. Education: Computer Science. Skills: Go, SQL, Flutter.", "not_invoice"},
		{"credit note", "Credit note CN-2026-002 correcting invoice INV-2026-001. Seller: Example Supplies Ltd. Refund due: EUR 25.00.", "invoice"},
	} {
		t.Run("classification/"+tc.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
			defer cancel()
			start := time.Now()
			value, err := classifier.Classify(ctx, config, key, invoice.SelectInvoiceClassificationInput(tc.text, 1))
			recordComparison(t, tc.name, "classification", start, err, value.Decision == tc.decision)
		})
	}
	t.Run("extraction", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
		defer cancel()
		start := time.Now()
		value, err := datasources.NewInvoiceExtractorDataSource(remote).InferClassified(ctx, config, key, invoiceText)
		pass := value != nil && value.Number == "EVAL-2026-001" && value.Currency == "EUR" && value.TotalGross == "119.00"
		recordComparison(t, "basic invoice", "extraction", start, err, pass)
	})
	t.Run("chat", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(t.Context(), 6*time.Minute)
		defer cancel()
		start := time.Now()
		provider := chatprovider.NewChatProviderRemoteDataSource()
		defer provider.Close()
		pass, err := compareChat(ctx, provider, model, endpoint, key, mode == "on")
		recordComparison(t, "search read answer", "chat", start, err, pass)
	})
}

func recordComparison(t *testing.T, name, task string, start time.Time, err error, pass bool) {
	code := ""
	var doc document.DocumentProcessingError
	var c chat.ChatProcessingError
	switch {
	case errors.As(err, &doc):
		code = doc.Code
	case errors.As(err, &c):
		code = c.Code
	case errors.Is(err, context.DeadlineExceeded):
		code = "timeout"
	case err != nil:
		code = "evaluation_failed"
	}
	value, _ := json.Marshal(map[string]any{"case": name, "task": task, "passed": pass && err == nil, "failure_code": code, "elapsed_ms": time.Since(start).Milliseconds()})
	fmt.Printf("AI_EVAL %s\n", value)
	if !pass || err != nil {
		t.Error("Evaluation case failed; see sanitized result")
	}
}

func compareChat(ctx context.Context, provider *chatprovider.ChatProviderRemoteDataSource, model, endpoint, key string, thinking bool) (bool, error) {
	input := chat.ChatInferenceInput{APIKey: key, Configuration: chat.ChatConfiguration{Provider: "openai", Model: model, BaseURL: endpoint, ThinkingEnabled: thinking}, Messages: []chat.ChatProviderMessage{{Role: "user", Content: "Search my Northwind electricity bill and read the document. What amount in EUR is due? Do not guess."}}}
	searched, read := false, false
	for round := 0; round <= chat.ChatMaxToolCalls; round++ {
		action, err := provider.Generate(ctx, input)
		if err != nil {
			return false, err
		}
		var result string
		switch action.Kind {
		case "list_tools":
			body, _ := json.Marshal(chatdata.NewChatToolCatalogPage(action.Offset))
			result = string(body)
		case "search_documents":
			searched = true
			result = `{"items":[{"documentId":"5e9c6190-4157-457f-89a4-a3c463764e18","title":"Northwind electricity bill","excerpt":"Read for the amount due."}]}`
		case "read_document":
			if !searched || action.DocumentID != "5e9c6190-4157-457f-89a4-a3c463764e18" {
				return false, nil
			}
			read = true
			result = `{"documentId":"5e9c6190-4157-457f-89a4-a3c463764e18","text":"Northwind electricity bill. Total amount due: 42.17 EUR."}`
		case "answer":
			answer := strings.ReplaceAll(action.Content, ",", ".")
			return searched && read && strings.Contains(answer, "42.17") && (strings.Contains(strings.ToUpper(answer), "EUR") || strings.Contains(answer, "€")), nil
		default:
			return false, nil
		}
		args := map[string]any{"offset": action.Offset}
		if action.Kind == "search_documents" {
			args["query"] = action.Query
		}
		if action.Kind == "read_document" {
			args["documentId"] = action.DocumentID
		}
		encoded, _ := json.Marshal(args)
		input.Messages = append(input.Messages, chat.ChatProviderMessage{Role: "assistant", ToolCall: &chat.ChatToolCall{ID: action.ToolCallID, Name: action.Kind, Arguments: string(encoded)}}, chat.ChatProviderMessage{Role: "tool", Content: result, ToolCallID: action.ToolCallID})
		input.ToolsUsed++
	}
	return false, nil
}
