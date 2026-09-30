package llm

import (
	"bytes"
	"encoding/json"
	"errors"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDocumentThinkingDefaultsAndPromptResponseDiagnostics(t *testing.T) {
	for _, tc := range []struct {
		name, metadata, task string
		think                bool
		tokens, budget       int
	}{
		{"boolean", `"thinking":{"values":[false,true],"default":false}`, "invoice_classification", false, 256, 256},
		{"legacy", `"capabilities":["completion","thinking"]`, "invoice_classification", false, 256, 256},
		{"level", `"thinking":{"values":["low","medium","high"],"default":"medium"}`, "invoice_classification", false, 256, 256},
		{"unsupported", `"thinking":{"values":[false],"default":false}`, "invoice_classification", false, 256, 256},
		{"unknown", `"capabilities":["completion"]`, "invoice_classification", false, 256, 256},
		{"properties boolean", `"thinking":{"values":[false,true],"default":false}`, "document_properties", false, 2048, 2048},
		{"properties legacy", `"capabilities":["completion","thinking"]`, "document_properties", false, 2048, 2048},
		{"properties level", `"thinking":{"values":["low","medium","high"],"default":"medium"}`, "document_properties", false, 2048, 2048},
		{"properties unsupported", `"thinking":{"values":[false],"default":false}`, "document_properties", false, 2048, 2048},
		{"properties unknown", `"capabilities":["completion"]`, "document_properties", false, 2048, 2048},
		{"extraction boolean", `"thinking":{"values":[false,true],"default":false}`, "invoice_extraction", false, 50000, 50000},
		{"extraction legacy", `"capabilities":["completion","thinking"]`, "invoice_extraction", false, 50000, 50000},
		{"extraction level", `"thinking":{"values":["low","medium","high"],"default":"medium"}`, "invoice_extraction", false, 50000, 50000},
		{"extraction unsupported", `"thinking":{"values":[false],"default":false}`, "invoice_extraction", false, 50000, 50000},
		{"extraction unknown", `"capabilities":["completion"]`, "invoice_extraction", false, 50000, 50000},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var logs bytes.Buffer
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/show" {
					_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":65536},` + tc.metadata + `}`))
					return
				}
				var request map[string]any
				if json.NewDecoder(r.Body).Decode(&request) != nil {
					t.Error("invalid request")
				}
				options := request["options"].(map[string]any)
				if request["think"] != tc.think || options["num_predict"] != float64(tc.budget) || options["num_ctx"] != float64(65536) || options["temperature"] != 0.2 {
					t.Errorf("incorrect thinking/context budget: %v %v", request["think"], options)
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"thinking": "SECRET_REASONING", "content": `{"decision":"not_invoice","reason":"other_document"}`}, "prompt_eval_count": 321, "eval_count": 123})
			}))
			defer server.Close()
			remote, err := NewDocumentPropertyRemoteDataSource(server.URL, slog.New(slog.NewJSONHandler(&logs, nil)))
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			content, err := remote.Generate(t.Context(), "ollama", "qwen3.5:4b", "", "SECRET_KEY", "Invoice task", "{}", "SECRET_DOCUMENT", tc.tokens, 0.2, false, false, 65536)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(content, "SECRET_REASONING") {
				t.Fatal("thinking leaked into final content")
			}
			var record map[string]any
			if json.Unmarshal(logs.Bytes(), &record) != nil || record["task"] != tc.task || record["prompt_tokens"] != float64(321) || record["generated_tokens"] != float64(123) || record["thinking_requested"] != tc.think {
				t.Fatalf("missing diagnostics: %s", logs.String())
			}
			if record["prompt"] != "Invoice task\nRequired JSON schema:\n{}\nBEGIN OCR DOCUMENT\nSECRET_DOCUMENT\nEND OCR DOCUMENT" || record["response_json"] != content {
				t.Fatal("missing original prompt or model response")
			}
			if strings.Contains(logs.String(), "SECRET_KEY") || strings.Contains(logs.String(), "SECRET_REASONING") {
				t.Fatal("credentials or reasoning leaked into diagnostics")
			}
		})
	}
}

func TestDocumentThinkingFailureCategories(t *testing.T) {
	for _, tc := range []struct{ name, finish, content, reasoning, code string }{
		{"output exhausted", "length", "", "reasoning", "output_limit"},
		{"empty final", "stop", "  ", "reasoning", "empty_response"},
		{"oversized", "stop", "ok", strings.Repeat("x", 300000), "response_too_large"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/show" {
					_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":65536},"capabilities":["thinking"]}`))
					return
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": tc.finish, "message": map[string]string{"content": tc.content, "thinking": tc.reasoning}})
			}))
			defer s.Close()
			remote, _ := NewDocumentPropertyRemoteDataSource(s.URL)
			defer remote.Close()
			_, err := remote.Generate(t.Context(), "ollama", "qwen3.5:4b", "", "", "Classify", "{}", "Document", 256, 0.2, false, false)
			var failure document.DocumentProcessingError
			if !errors.As(err, &failure) || failure.Code != tc.code {
				t.Fatalf("expected %s: %v", tc.code, err)
			}
		})
	}
}
