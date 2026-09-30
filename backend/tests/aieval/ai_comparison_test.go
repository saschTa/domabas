//go:build ai_eval

package aieval_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
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
	contextLength, err := strconv.Atoi(os.Getenv("AI_EVAL_CONTEXT"))
	if err != nil || endpoint == "" || model == "" || (mode != "on" && mode != "off") {
		t.Fatal("Use task evaluate:ai with explicit endpoints and model")
	}
	client := &http.Client{Timeout: 3 * time.Minute, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	defer client.CloseIdleConnections()
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/show" && r.URL.Path != "/api/chat" {
			http.Error(w, "Evaluation never pulls models", 400)
			return
		}
		body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		if err != nil {
			w.WriteHeader(502)
			return
		}
		if r.URL.Path == "/api/chat" {
			var value map[string]any
			if json.Unmarshal(body, &value) != nil {
				w.WriteHeader(400)
				return
			}
			value["think"] = mode == "on"
			body, _ = json.Marshal(value)
		}
		request, err := http.NewRequestWithContext(r.Context(), http.MethodPost, endpoint+r.URL.Path, bytes.NewReader(body))
		if err != nil {
			w.WriteHeader(502)
			return
		}
		request.Header.Set("Content-Type", "application/json")
		response, err := client.Do(request)
		if err != nil {
			w.WriteHeader(502)
			return
		}
		defer response.Body.Close()
		body, err = io.ReadAll(io.LimitReader(response.Body, 2<<20))
		if err != nil {
			w.WriteHeader(502)
			return
		}
		if mode == "off" && r.URL.Path == "/api/show" && response.StatusCode == 200 {
			var value map[string]any
			if json.Unmarshal(body, &value) != nil {
				w.WriteHeader(502)
				return
			}
			value["thinking"] = map[string]any{"values": []bool{false}, "default": false}
			body, _ = json.Marshal(value)
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(response.StatusCode)
		_, _ = w.Write(body)
	}))
	defer proxy.Close()
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	remote, err := llm.NewDocumentPropertyRemoteDataSource(proxy.URL, logger)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	classifier := datasources.NewInvoiceClassifierDataSource(remote)
	config := document.DocumentLLMConfiguration{Provider: "ollama", Model: model, ContextLength: contextLength}
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
			value, err := classifier.Classify(ctx, config, "", invoice.SelectInvoiceClassificationInput(tc.text, 1))
			recordComparison(t, tc.name, "classification", start, err, value.Decision == tc.decision)
		})
	}
	t.Run("extraction", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
		defer cancel()
		start := time.Now()
		value, err := datasources.NewInvoiceExtractorDataSource(remote).InferClassified(ctx, config, "", invoiceText)
		pass := value != nil && value.Number == "EVAL-2026-001" && value.Currency == "EUR" && value.TotalGross == "119.00"
		recordComparison(t, "basic invoice", "extraction", start, err, pass)
	})
	t.Run("chat", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(t.Context(), 6*time.Minute)
		defer cancel()
		start := time.Now()
		provider, err := chatprovider.NewChatProviderRemoteDataSource(proxy.URL, logger)
		if err != nil {
			t.Fatal(err)
		}
		defer provider.Close()
		pass, err := compareChat(ctx, provider, model, contextLength)
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

func compareChat(ctx context.Context, provider *chatprovider.ChatProviderRemoteDataSource, model string, contextLength int) (bool, error) {
	input := chat.ChatInferenceInput{Configuration: chat.ChatConfiguration{Provider: "ollama", Model: model, ContextLength: contextLength}, Messages: []chat.ChatProviderMessage{{Role: "user", Content: "Search my Northwind electricity bill and read the document. What amount in EUR is due? Do not guess."}}}
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
		input.Messages = append(input.Messages, chat.ChatProviderMessage{Role: "assistant", ToolCall: &chat.ChatToolCall{ID: "evaluation-tool", Name: action.Kind, Arguments: string(encoded)}}, chat.ChatProviderMessage{Role: "tool", Content: result, ToolCallID: "evaluation-tool"})
		input.ToolsUsed++
	}
	return false, nil
}
