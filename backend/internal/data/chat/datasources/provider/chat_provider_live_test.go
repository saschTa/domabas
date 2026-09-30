//go:build llm_live

package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	data "github.com/domabas/domabas/backend/internal/data/chat/models"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

type chatLiveResponseTransport struct {
	base http.RoundTripper
	test *testing.T
}

func (transport chatLiveResponseTransport) CloseIdleConnections() {
	if closer, ok := transport.base.(interface{ CloseIdleConnections() }); ok {
		closer.CloseIdleConnections()
	}
}

func (transport chatLiveResponseTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	response, err := transport.base.RoundTrip(request)
	if err == nil && request.URL.Path == "/api/chat" {
		body, readErr := io.ReadAll(io.LimitReader(response.Body, chatProviderResponseLimit+1))
		response.Body.Close()
		response.Body = io.NopCloser(bytes.NewReader(body))
		if readErr != nil {
			return response, readErr
		}
		transport.test.Logf("Synthetic Qwen response: %s", body)
	}
	return response, err
}

func TestLiveQwenChatCallsDocumentToolsAndAnswers(t *testing.T) {
	endpoint := os.Getenv("LLM_OLLAMA_URL")
	if endpoint == "" {
		t.Fatal("LLM_OLLAMA_URL is required for live chat tests")
	}
	provider, err := NewChatProviderRemoteDataSource(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	defer provider.Close()
	provider.client.Transport = chatLiveResponseTransport{base: provider.client.Transport, test: t}
	ctx, cancel := context.WithTimeout(t.Context(), 6*time.Minute)
	defer cancel()
	input := m.ChatInferenceInput{Configuration: m.ChatConfiguration{Provider: "ollama", Model: "qwen3.5:4b"}, Messages: []m.ChatProviderMessage{{Role: "user", Content: "Use search_documents to find my Northwind electricity bill, then use read_document to read its amount. What amount in EUR is due? Search before answering and do not guess. Report the amount with its currency."}}}
	searched, read := false, false
	for round := 0; round <= m.ChatMaxToolCalls; round++ {
		action, err := provider.Generate(ctx, input)
		if err != nil {
			t.Fatalf("Qwen action round %d: %v", round+1, err)
		}
		var result string
		switch action.Kind {
		case "list_tools":
			body, err := json.Marshal(data.NewChatToolCatalogPage(action.Offset))
			if err != nil {
				t.Fatal(err)
			}
			result = string(body)
		case "search_documents":
			searched = true
			result = `{"items":[{"documentId":"5e9c6190-4157-457f-89a4-a3c463764e18","title":"Northwind electricity bill","excerpt":"Read this bill to find the amount due."}]}`
		case "read_document":
			if !searched || action.DocumentID != "5e9c6190-4157-457f-89a4-a3c463764e18" {
				t.Fatalf("Qwen requested an unprovided document: %+v", action)
			}
			read = true
			result = `{"documentId":"5e9c6190-4157-457f-89a4-a3c463764e18","title":"Northwind electricity bill","text":"Northwind Energy. Electricity bill. Total amount due: 42.17 EUR. Please pay by 30 September 2026."}`
		case "answer":
			text := strings.ReplaceAll(action.Content, ",", ".")
			if !searched || !read || !strings.Contains(text, "42.17") || (!strings.Contains(strings.ToUpper(text), "EUR") && !strings.Contains(text, "€")) {
				t.Fatalf("Qwen answer did not use retrieved evidence: %s", action.Content)
			}
			return
		default:
			t.Fatalf("unexpected Qwen action %s", action.Kind)
		}
		arguments := map[string]any{"offset": action.Offset}
		if action.Kind == "search_documents" {
			arguments["query"] = action.Query
		} else if action.Kind == "read_document" {
			arguments["documentId"] = action.DocumentID
		}
		encoded, err := json.Marshal(arguments)
		if err != nil {
			t.Fatal(err)
		}
		input.Messages = append(input.Messages, m.ChatProviderMessage{Role: "assistant", ToolCall: &m.ChatToolCall{ID: "document-context", Name: action.Kind, Arguments: string(encoded)}}, m.ChatProviderMessage{Role: "tool", Content: result, ToolCallID: "document-context"})
		input.ToolsUsed++
	}
	t.Fatal("Qwen exhausted tool rounds without an answer")
}
