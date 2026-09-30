package provider

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

type chatDeadlineTransport struct {
	t        *testing.T
	expected time.Duration
}

func (transport chatDeadlineTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	deadline, ok := request.Context().Deadline()
	remaining := time.Until(deadline)
	if !ok || remaining < transport.expected-time.Second || remaining > transport.expected {
		transport.t.Errorf("unexpected provider request deadline: %v", remaining)
	}
	return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(`{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Done"}}]}`)), Header: make(http.Header)}, nil
}

func TestProviderQueueWaitDeadlinePreservesEarlierCancellation(t *testing.T) {
	for _, timeout := range []time.Duration{time.Hour, time.Minute} {
		t.Run(timeout.String(), func(t *testing.T) {
			provider, err := NewChatProviderRemoteDataSource("http://ollama.test")
			if err != nil {
				t.Fatal(err)
			}
			defer provider.Close()
			provider.client.Transport = chatDeadlineTransport{t: t, expected: min(timeout, 30*time.Minute)}
			ctx, cancel := context.WithTimeout(t.Context(), timeout)
			defer cancel()
			if _, err := provider.Generate(ctx, chatInferenceFixture("openai", "http://provider.test")); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func chatProviderFixture(t *testing.T, handler http.HandlerFunc) (*ChatProviderRemoteDataSource, string) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	provider, err := NewChatProviderRemoteDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(provider.Close)
	return provider, server.URL
}

func chatInferenceFixture(provider, url string) m.ChatInferenceInput {
	return m.ChatInferenceInput{Configuration: m.ChatConfiguration{Provider: provider, Model: "qwen3.5:4b", BaseURL: url + "/v1"}, APIKey: "test-only-secret", Messages: []m.ChatProviderMessage{{Role: "user", Content: "Find my bill"}}}
}

func TestOllamaQwenStructuredActionsAndPull(t *testing.T) {
	var pulled atomic.Bool
	provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "" {
			t.Error("internal request included credential")
		}
		switch r.URL.Path {
		case "/api/show":
			if !pulled.Load() {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			fmt.Fprint(w, chatModelContextFixture)
		case "/api/pull":
			pulled.Store(true)
			fmt.Fprint(w, `{"status":"success"}`)
		case "/api/chat":
			var body map[string]json.RawMessage
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if !pulled.Load() || body["format"] == nil || body["tools"] != nil {
				t.Error("missing structured fallback or unexpected native tools")
			}
			var messages []ChatProviderMessage
			if err := json.Unmarshal(body["messages"], &messages); err != nil {
				t.Fatal(err)
			}
			if len(messages) != 1 || messages[0].Role != "user" || !strings.Contains(messages[0].Content, "Find my bill") {
				t.Error("invalid Qwen prompt")
			}
			json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"content": `{"action":"search_documents","content":"","query":"electricity bill","documentId":"","offset":10}`}})
		default:
			t.Errorf("unexpected request %s", r.URL.Path)
		}
	})
	action, err := provider.Generate(t.Context(), chatInferenceFixture("ollama", ""))
	if err != nil || action.Kind != "search_documents" || action.Offset != 10 || action.Query != "electricity bill" {
		t.Fatalf("action=%+v err=%v", action, err)
	}
}

func TestExternalNativeToolRoundTrip(t *testing.T) {
	var calls atomic.Int32
	provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer test-only-secret" {
			t.Error("external endpoint or credential missing")
		}
		var request struct {
			Messages      []ChatProviderMessage `json:"messages"`
			Tools         []any                 `json:"tools"`
			Parallel      bool                  `json:"parallel_tool_calls"`
			Options       json.RawMessage       `json:"options"`
			ContextLength json.RawMessage       `json:"contextLength"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		if len(request.Tools) != 3 || request.Parallel || request.Messages[0].Role != "system" || request.Options != nil || request.ContextLength != nil {
			t.Error("invalid native tools request")
		}
		if calls.Add(1) == 1 {
			json.NewEncoder(w).Encode(ChatCompletionResponse{Choices: []ChatCompletionChoice{{FinishReason: "tool_calls", Message: ChatProviderMessage{Role: "assistant", ToolCalls: []ChatProviderToolCall{{ID: "call-one", Type: "function", Function: ChatProviderToolFunction{Name: "search_documents", Arguments: `{"query":"bill","offset":0}`}}}}}}})
			return
		}
		if len(request.Messages) != 4 || request.Messages[2].ToolCalls[0].ID != "call-one" || request.Messages[3].ToolCallID != "call-one" || request.Messages[3].Role != "tool" {
			t.Error("native callback identity not preserved")
		}
		json.NewEncoder(w).Encode(ChatCompletionResponse{Choices: []ChatCompletionChoice{{FinishReason: "stop", Message: ChatProviderMessage{Role: "assistant", Content: "Your electricity bill is €42."}}}})
	})
	input := chatInferenceFixture("openai", url)
	input.Configuration.ContextLength = 65536
	action, err := provider.Generate(t.Context(), input)
	if err != nil || action.ToolCallID != "call-one" || action.Query != "bill" {
		t.Fatalf("action=%+v err=%v", action, err)
	}
	input.Messages = append(input.Messages, m.ChatProviderMessage{Role: "assistant", ToolCall: &m.ChatToolCall{ID: action.ToolCallID, Name: action.Kind, Arguments: `{"query":"bill","offset":0}`}}, m.ChatProviderMessage{Role: "tool", ToolCallID: action.ToolCallID, Content: `{"documents":[{"title":"Electricity bill","amount":"42 EUR"}]}`})
	answer, err := provider.Generate(t.Context(), input)
	if err != nil || answer.Kind != "answer" || !strings.Contains(answer.Content, "€42") {
		t.Fatalf("answer=%+v err=%v", answer, err)
	}
}

func TestProviderRejectsInvalidStructuredActions(t *testing.T) {
	for _, response := range []string{
		`{"action":"answer","content":"done"}`,
		`{"action":"answer","content":"done","query":null,"documentId":"","offset":0}`,
		`{"action":"search_documents","content":"","query":"bill","documentId":"","offset":0,"accountId":"other"}`,
		`{"action":"read_document","content":"","query":"","documentId":"not-a-uuid","offset":0}`,
		`{"action":"shell","content":"","query":"rm","documentId":"","offset":0}`,
		`{"action":"search_documents","content":"","query":"bill","documentId":"","offset":-1}`,
		`{"action":"answer","content":"done","query":"","documentId":"","offset":0} {}`,
		`{"action":"answer","content":"done","content":"replaced","query":"","documentId":"","offset":0}`,
	} {
		t.Run(response, func(t *testing.T) {
			provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/show" {
					fmt.Fprint(w, chatModelContextFixture)
					return
				}
				json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"content": response}})
			})
			_, err := provider.Generate(t.Context(), chatInferenceFixture("ollama", ""))
			var failure m.ChatProcessingError
			if !errors.As(err, &failure) || failure.Code != "invalid_response" || failure.Retryable {
				t.Fatalf("unexpected error %v", err)
			}
		})
	}
}

func TestExternalRejectsMalformedAndParallelTools(t *testing.T) {
	for _, arguments := range []string{`{"query":"bill"}`, `{"query":"bill","query":"replacement","offset":0}`, `{"query":"bill","offset":null}`, `{"query":"bill","offset":0,"namespace":"other"}`, `[]`} {
		t.Run(arguments, func(t *testing.T) {
			provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				json.NewEncoder(w).Encode(ChatCompletionResponse{Choices: []ChatCompletionChoice{{FinishReason: "tool_calls", Message: ChatProviderMessage{ToolCalls: []ChatProviderToolCall{{ID: "one", Type: "function", Function: ChatProviderToolFunction{Name: "search_documents", Arguments: arguments}}}}}}})
			})
			if _, err := provider.Generate(t.Context(), chatInferenceFixture("openai", url)); err == nil {
				t.Fatal("invalid arguments accepted")
			}
		})
	}
	provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(ChatCompletionResponse{Choices: []ChatCompletionChoice{{FinishReason: "tool_calls", Message: ChatProviderMessage{ToolCalls: []ChatProviderToolCall{{ID: "one"}, {ID: "two"}}}}}})
	})
	if _, err := provider.Generate(t.Context(), chatInferenceFixture("openai", url)); err == nil {
		t.Fatal("parallel calls accepted")
	}
}

func TestProviderRedirectAndOversizedResponses(t *testing.T) {
	var reached atomic.Bool
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { reached.Store(true) }))
	defer target.Close()
	provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	})
	if _, err := provider.Generate(t.Context(), chatInferenceFixture("openai", url)); err == nil || reached.Load() {
		t.Fatalf("redirect followed: %v", err)
	}
	large, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, strings.Repeat("x", chatProviderResponseLimit+1))
	})
	_, err := large.Generate(t.Context(), chatInferenceFixture("openai", url))
	var failure m.ChatProcessingError
	if !errors.As(err, &failure) || failure.Code != "resource_limit" {
		t.Fatalf("oversized error %v", err)
	}
}

func TestProviderOverloadIsSanitizedAndCancellationPropagates(t *testing.T) {
	provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(429)
		fmt.Fprint(w, "private upstream failure and test-only-secret")
	})
	_, err := provider.Generate(t.Context(), chatInferenceFixture("openai", url))
	var failure m.ChatProcessingError
	if !errors.As(err, &failure) || !failure.Retryable || strings.Contains(err.Error(), "secret") {
		t.Fatalf("unsafe error %v", err)
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err = provider.Generate(ctx, chatInferenceFixture("openai", url)); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancellation lost: %v", err)
	}
}

func TestProviderCatalogPaginationAndInternalOrigin(t *testing.T) {
	provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.URL.Path != "/api/tags" {
			t.Errorf("unexpected catalog request %s %s", r.Method, r.URL.Path)
		}
		fmt.Fprint(w, `{"models":[{"name":"z"},{"name":"a"},{"name":"b"},{"name":"a"}]}`)
	})
	first, err := provider.Models(t.Context(), 2, 0)
	if err != nil || len(first.Items) != 2 || first.Items[0].Name != "a" || first.NextOffset == nil || *first.NextOffset != 2 {
		t.Fatalf("first=%+v err=%v", first, err)
	}
	last, err := provider.Models(t.Context(), 2, *first.NextOffset)
	if err != nil || len(last.Items) != 1 || last.Items[0].Name != "z" || last.NextOffset != nil {
		t.Fatalf("last=%+v err=%v", last, err)
	}
	empty, err := provider.Models(t.Context(), 2, 100)
	if err != nil || empty.Items == nil || len(empty.Items) != 0 {
		t.Fatalf("empty=%+v err=%v", empty, err)
	}
	origin, err := NewChatProviderRemoteDataSource("http://OLLAMA:80")
	if err != nil {
		t.Fatal(err)
	}
	defer origin.Close()
	for _, tc := range []struct {
		configuration m.ChatConfiguration
		want          bool
	}{
		{m.ChatConfiguration{Provider: "ollama"}, true},
		{m.ChatConfiguration{Provider: "openai", BaseURL: "http://ollama/v1"}, true},
		{m.ChatConfiguration{Provider: "openai", BaseURL: "http://ollama:81/v1"}, false},
		{m.ChatConfiguration{Provider: "openai", BaseURL: "https://ollama/v1"}, false},
		{m.ChatConfiguration{Provider: "openai", BaseURL: "http://external/v1"}, false},
	} {
		if got := origin.UsesInternalRuntime(tc.configuration); got != tc.want {
			t.Errorf("origin=%+v got=%t", tc.configuration, got)
		}
	}
}

func TestProviderContextBoundRejectsBeforeNetwork(t *testing.T) {
	var reached atomic.Bool
	provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) { reached.Store(true) })
	input := chatInferenceFixture("openai", url)
	input.Messages[0].Content = strings.Repeat("ü", m.ChatMaxContextCharacters+1)
	if _, err := provider.Generate(t.Context(), input); err == nil || reached.Load() {
		t.Fatalf("oversized context submitted: %v", err)
	}
}

func TestChatCatalogDiscoveryBothProviders(t *testing.T) {
	for _, kind := range []string{"ollama", "openai"} {
		for _, arguments := range []string{`{"offset":2}`, `{"offset":-1}`, `{"offset":10001}`, `{"offset":null}`, `{"offset":0,"offset":2}`, `{"offset":0,"query":"x"}`, `{}`} {
			t.Run(kind+arguments, func(t *testing.T) {
				provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
					if r.URL.Path == "/api/show" {
						fmt.Fprint(w, chatModelContextFixture)
						return
					}
					if kind == "openai" {
						json.NewEncoder(w).Encode(ChatCompletionResponse{Choices: []ChatCompletionChoice{{FinishReason: "tool_calls", Message: ChatProviderMessage{ToolCalls: []ChatProviderToolCall{{ID: "catalog-2", Type: "function", Function: ChatProviderToolFunction{Name: "list_tools", Arguments: arguments}}}}}}})
						return
					}
					content := strings.TrimSuffix(arguments, "}") + `,"action":"list_tools","content":"","query":"","documentId":""}`
					if arguments == `{}` {
						content = `{"action":"list_tools","content":"","query":"","documentId":""}`
					}
					json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"content": content}})
				})
				action, err := provider.Generate(t.Context(), chatInferenceFixture(kind, url))
				if arguments == `{"offset":2}` {
					if err != nil || action.Kind != "list_tools" || action.Offset != 2 {
						t.Fatal(action, err)
					}
				} else if err == nil {
					t.Fatal("invalid catalog request accepted", action)
				}
			})
		}
	}
}

func TestChatProvidersConstrainFinalAnswerAfterThirtyCalls(t *testing.T) {
	testChatProvidersConstrainAnswer(t, 30, false)
}

func TestChatProvidersConstrainEarlyNoProgressAnswer(t *testing.T) {
	testChatProvidersConstrainAnswer(t, 3, true)
}

func testChatProvidersConstrainAnswer(t *testing.T, used int, answerOnly bool) {
	t.Helper()
	for _, kind := range []string{"ollama", "openai"} {
		t.Run(kind, func(t *testing.T) {
			provider, url := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/show" {
					fmt.Fprint(w, chatModelContextFixture)
					return
				}
				var body map[string]json.RawMessage
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				if !strings.Contains(string(body["messages"]), fmt.Sprintf("Remaining tool calls: %d", 30-used)) {
					t.Fatal("missing exhausted budget")
				}
				if kind == "openai" {
					if string(body["tool_choice"]) != `"none"` {
						t.Fatal("tools still enabled")
					}
					json.NewEncoder(w).Encode(ChatCompletionResponse{Choices: []ChatCompletionChoice{{FinishReason: "stop", Message: ChatProviderMessage{Content: "Evidence answer"}}}})
					return
				}
				if strings.Contains(string(body["format"]), "search_documents") || strings.Contains(string(body["format"]), "list_tools") || !strings.Contains(string(body["format"]), "answer") {
					t.Fatal("not answer-only schema", string(body["format"]))
				}
				json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"content": `{"action":"answer","content":"Evidence answer","query":"","documentId":"","offset":0}`}})
			})
			input := chatInferenceFixture(kind, url)
			input.ToolsUsed = used
			input.AnswerOnly = answerOnly
			action, err := provider.Generate(t.Context(), input)
			if err != nil || action.Kind != "answer" {
				t.Fatal(action, err)
			}
		})
	}
}
