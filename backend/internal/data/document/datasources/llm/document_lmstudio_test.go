package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestRejectedProviderCannotHoldDiagnosticsOpen(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		w.(http.Flusher).Flush()
		<-request.Context().Done()
	}))
	defer server.Close()
	remote, _ := NewDocumentPropertyRemoteDataSource(server.URL)
	defer remote.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	_, err := remote.Generate(ctx, "openai", "fixture", server.URL, "", "Task", "{}", "Text", 256, 0.2, true, false)
	var failure m.DocumentProcessingError
	if !errors.As(err, &failure) || failure.Code != "inference_unavailable" || ctx.Err() != nil {
		t.Fatalf("provider held rejection open until caller timeout: %v", err)
	}
}

func TestExternalCompatibilityUsesAcceptedSchemaForEveryDocumentTask(t *testing.T) {
	for _, compatible := range []bool{false, true} {
		for _, tokens := range []int{256, 2048, 50000} {
			t.Run(strings.Join([]string{map[bool]string{false: "standard", true: "lmstudio"}[compatible], map[int]string{256: "classification", 2048: "properties", 50000: "invoice"}[tokens]}, "/"), func(t *testing.T) {
				const schema = `{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}`
				calls := 0
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
					calls++
					var payload struct {
						Model          string `json:"model"`
						Stream         bool   `json:"stream"`
						MaxTokens      int    `json:"max_tokens"`
						ResponseFormat struct {
							Type       string `json:"type"`
							JSONSchema struct {
								Name   string          `json:"name"`
								Schema json.RawMessage `json:"schema"`
								Strict *bool           `json:"strict"`
							} `json:"json_schema"`
						} `json:"response_format"`
					}
					if err := json.NewDecoder(request.Body).Decode(&payload); err != nil {
						t.Error(err)
					}
					if request.URL.Path != "/v1/chat/completions" || payload.Model != "accepted-model" || payload.Stream || payload.MaxTokens != tokens {
						t.Errorf("unexpected request: %+v", payload)
					}
					format := payload.ResponseFormat
					if compatible {
						if format.Type != "json_schema" || string(format.JSONSchema.Schema) != schema || format.JSONSchema.Name == "" || format.JSONSchema.Strict != nil {
							t.Errorf("schema was not sent intact: %+v", format)
						}
					} else if format.Type != "json_object" || len(format.JSONSchema.Schema) != 0 {
						t.Errorf("default wire format changed: %+v", format)
					}
					_, _ = io.WriteString(w, `{"choices":[{"finish_reason":"stop","message":{"content":"{\"answer\":\"ok\"}"}}]}`)
				}))
				defer server.Close()
				remote, _ := NewDocumentPropertyRemoteDataSource(server.URL)
				defer remote.Close()
				output, err := remote.Generate(t.Context(), "openai", "accepted-model", server.URL+"/v1", "", "Return JSON", schema, "Synthetic text", tokens, 0.2, compatible, false)
				if err != nil || output != `{"answer":"ok"}` || calls != 1 {
					t.Fatalf("inference changed or retried: %q %d %v", output, calls, err)
				}
			})
		}
	}
}

func TestExternalInferenceDiagnosticsExplainRejectionWithoutProviderContent(t *testing.T) {
	for _, scenario := range []struct {
		name, body, kind, reason, outcome string
		status                            int
	}{
		{"lmstudio", `{"error":"'response_format.type' must be 'json_schema' or 'text'; SECRET_KEY SECRET_DOCUMENT"}`, "http_rejection", "response_format_requires_json_schema", "inference_unavailable", 400},
		{"nested", `{"error":{"message":"Context length exceeded: SECRET_DOCUMENT"}}`, "http_rejection", "context_limit", "inference_unavailable", 400},
		{"unauthorized", `{"error":"SECRET_KEY"}`, "http_rejection", "unclassified", "inference_unavailable", 401},
		{"oversized error", strings.Repeat("SECRET_KEY", 1000), "http_rejection", "unclassified", "inference_unavailable", 400},
		{"overload", `{"error":"SECRET_KEY"}`, "http_rejection", "unclassified", "overloaded", 503},
		{"invalid JSON", "SECRET_DOCUMENT", "response_decode", "", "processing_failed", 200},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var logs bytes.Buffer
			calls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
				calls++
				w.WriteHeader(scenario.status)
				_, _ = io.WriteString(w, scenario.body)
			}))
			defer server.Close()
			remote, _ := NewDocumentPropertyRemoteDataSource(server.URL, slog.New(slog.NewJSONHandler(&logs, nil)))
			defer remote.Close()
			_, err := remote.Generate(t.Context(), "openai", "fixture", server.URL, "SECRET_KEY", "SECRET_PROMPT", "{}", "SECRET_DOCUMENT", 256, 0.2, false, false)
			if err == nil || calls != 1 {
				t.Fatalf("rejection lost or automatically retried: %d %v", calls, err)
			}
			var record map[string]any
			if json.Unmarshal(logs.Bytes(), &record) != nil || record["http_status"] != float64(scenario.status) || record["error_kind"] != scenario.kind || record["provider_error_reason"] != scenario.reason || record["outcome"] != scenario.outcome || record["task"] != "invoice_classification" || record["response_format"] != "json_object" || record["elapsed"] == nil {
				t.Fatalf("missing safe diagnostics: %s", logs.String())
			}
			if strings.Contains(logs.String(), "SECRET") || strings.Contains(logs.String(), server.URL) || strings.Contains(err.Error(), "SECRET") {
				t.Fatal("provider content or credentials leaked")
			}
		})
	}
}

func TestExternalInferenceDiagnosticsRetainCancellationAndUsage(t *testing.T) {
	for _, cancelled := range []bool{false, true} {
		var logs bytes.Buffer
		remote, _ := NewDocumentPropertyRemoteDataSource("http://model.test", slog.New(slog.NewJSONHandler(&logs, nil)))
		ctx, cancel := context.WithCancel(t.Context())
		remote.client.Transport = documentInferenceTransport(func(request *http.Request) (*http.Response, error) {
			if cancelled {
				cancel()
				return nil, request.Context().Err()
			}
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"choices":[{"finish_reason":"stop","message":{"content":"","reasoning_content":"SECRET_REASONING"}}],"usage":{"prompt_tokens":21,"completion_tokens":34}}`)), Header: http.Header{}}, nil
		})
		_, err := remote.Generate(ctx, "openai", "fixture", "http://model.test", "", "Task", "{}", "Text", 2048, 0.2, true, false)
		cancel()
		remote.Close()
		var record map[string]any
		if json.Unmarshal(logs.Bytes(), &record) != nil || record["response_format"] != "json_schema" || strings.Contains(logs.String(), "SECRET") {
			t.Fatalf("unsafe or absent diagnostics: %s", logs.String())
		}
		if cancelled {
			if !errors.Is(err, context.Canceled) || record["outcome"] != "cancelled" {
				t.Fatalf("cancellation lost: %s %v", logs.String(), err)
			}
		} else {
			var failure m.DocumentProcessingError
			if !errors.As(err, &failure) || failure.Code != "empty_response" || record["outcome"] != "empty_response" || record["reasoning_characters"] != float64(16) || record["prompt_tokens"] != float64(21) || record["generated_tokens"] != float64(34) {
				t.Fatalf("reasoning mistaken for output or usage lost: %s %v", logs.String(), err)
			}
		}
	}
}
