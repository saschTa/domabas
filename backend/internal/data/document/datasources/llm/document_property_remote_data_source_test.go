package llm

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

const properties = `{"description":"Invoice summary","tags":["invoice"],"sender":"Example","recipients":[],"documentDate":"2026-09-19","subject":"Invoice"}`

func TestPostalAddressPropertiesBecomeValidSingleLineMetadata(t *testing.T) {
	for _, provider := range []string{"ollama", "openai"} {
		t.Run(provider, func(t *testing.T) {
			content := `{"description":"Consulting services.\nPayment due in 14 days.","tags":["office\tservices","invoice"],"sender":" Example Büro GmbH\r\nSample Street 1\n10115 Berlin ","recipients":["Sample Customer AG\nOther Street 2\t20095 Hamburg"],"documentDate":"2026-07-25","subject":" Invoice\r\nEXAMPLE-1001 "}`
			server := propertyResponseServer(t, provider, content)
			defer server.Close()
			remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			got, err := remote.Extract(t.Context(), provider, "model", server.URL, "", "Synthetic invoice with postal addresses", false, false)
			if err != nil {
				t.Fatal(err)
			}
			if got.Sender != "Example Büro GmbH Sample Street 1 10115 Berlin" || !slices.Equal(got.Recipients, []string{"Sample Customer AG Other Street 2 20095 Hamburg"}) || got.Subject != "Invoice EXAMPLE-1001" || !slices.Equal(got.Tags, []string{"office services", "invoice"}) || got.Description != "Consulting services.\nPayment due in 14 days." {
				t.Fatalf("address content or description formatting changed: %+v", got)
			}
			if _, err := (m.DocumentMetadata{Title: "Invoice", Description: got.Description, Sender: got.Sender, Recipients: got.Recipients, Tags: got.Tags, Subject: got.Subject, DocumentDate: got.DocumentDate}).Normalize(); err != nil {
				t.Fatalf("extracted properties cannot be saved: %v", err)
			}
		})
	}
}

func TestPropertyWhitespaceNormalizationPreservesInvalidDataForValidation(t *testing.T) {
	for name, overrides := range map[string]map[string]any{
		"control character":    {"sender": "Example\x00Company"},
		"oversized sender":     {"sender": strings.Repeat("x", 321)},
		"invalid date":         {"documentDate": "2026-02-30"},
		"duplicate recipients": {"recipients": []string{"Example\nCustomer", "Example Customer"}},
		"duplicate tags":       {"tags": []string{"office\tservices", "office services"}},
		"empty recipient":      {"recipients": []string{"\r\n\t"}},
	} {
		t.Run(name, func(t *testing.T) {
			var payload map[string]any
			if err := json.Unmarshal([]byte(properties), &payload); err != nil {
				t.Fatal(err)
			}
			for key, value := range overrides {
				payload[key] = value
			}
			content, err := json.Marshal(payload)
			if err != nil {
				t.Fatal(err)
			}
			server := propertyResponseServer(t, "openai", string(content))
			defer server.Close()
			remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			got, err := remote.Extract(t.Context(), "openai", "model", server.URL, "", "Synthetic invoice", false, false)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := (m.DocumentMetadata{Title: "Invoice", Description: got.Description, Sender: got.Sender, Recipients: got.Recipients, Tags: got.Tags, Subject: got.Subject, DocumentDate: got.DocumentDate}).Normalize(); err == nil {
				t.Fatal("invalid generated data became valid", got)
			}
		})
	}
}

func propertyResponseServer(t *testing.T, provider, content string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/api/show" {
			_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`))
			return
		}
		message := map[string]string{"content": content}
		if provider == "ollama" {
			_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": message})
		} else {
			_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": message}}})
		}
	}))
}

func TestOllamaPullSelectedMissingModelAndBoundedChat(t *testing.T) {
	installed := false
	pulls, chats, shows := 0, 0, 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body["model"] != "qwen3.5:4b" || req.Header.Get("Authorization") != "" {
			t.Error("wrong model or leaked external credential")
		}
		switch req.URL.Path {
		case "/api/show":
			shows++
			if !installed {
				w.WriteHeader(404)
				return
			}
			_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`))
		case "/api/pull":
			pulls++
			installed = true
			if body["stream"] != false {
				t.Error("unbounded pull")
			}
			_, _ = w.Write([]byte(`{"status":"success"}`))
		case "/api/chat":
			chats++
			if body["options"].(map[string]any)["temperature"] != float64(0.2) {
				t.Error("property extraction temperature changed")
			}
			format, ok := body["format"].(map[string]any)
			if body["stream"] != false || !ok || format["additionalProperties"] != false || len(format["required"].([]any)) != 6 {
				t.Error("unbounded completion")
			}
			messages := body["messages"].([]any)
			if len(messages) != 1 || messages[0].(map[string]any)["role"] != "user" {
				t.Fatal("Qwen instructions and document must share one user turn")
			}
			content := messages[0].(map[string]any)["content"].(string)
			if !strings.Contains(content, propertySchema) || !strings.HasSuffix(content, "\nBEGIN OCR DOCUMENT\n"+strings.Repeat("ü", 100000)+"\nEND OCR DOCUMENT") {
				t.Error("schema grounding or bounded OCR input missing")
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"content": properties}})
		default:
			t.Error("unexpected path", req.URL.Path)
			w.WriteHeader(404)
		}
	}))
	defer server.Close()
	r, err := NewDocumentPropertyRemoteDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	for range 2 {
		v, err := r.Extract(t.Context(), "ollama", "qwen3.5:4b", "", "never-forward", strings.Repeat("ü", 100001), false, false)
		if err != nil || v.Subject != "Invoice" {
			t.Fatal(v, err)
		}
	}
	if pulls != 1 || chats != 2 || shows != 3 {
		t.Fatalf("pulls=%d chats=%d shows=%d", pulls, chats, shows)
	}
}

func TestInferencePreservesSelectedInvoiceInput(t *testing.T) {
	for _, provider := range []string{"ollama", "openai"} {
		for _, scenario := range []struct {
			name               string
			characters, tokens int
		}{
			{"classification", 20000, 256},
			{"wider classification", 50000, 256},
			{"extraction", 100000, 50000},
		} {
			t.Run(provider+"/"+scenario.name, func(t *testing.T) {
				text := strings.Repeat("ä", scenario.characters-4) + "TAIL"
				content := `{}`
				if scenario.name == "extraction" {
					content = `{"invoice":{"notes":["` + strings.Repeat(strings.Repeat("ä", 3000)+`","`, 49) + strings.Repeat("ä", 3000) + `"]}}`
				}
				var received string
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
					if req.URL.Path == "/api/show" {
						_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`))
						return
					}
					var body struct {
						Messages []struct{ Content string }
						Options  struct {
							Temperature float64
							Context     int `json:"num_ctx"`
							Tokens      int `json:"num_predict"`
						}
						Temperature float64
						MaxTokens   int `json:"max_tokens"`
					}
					if err := json.NewDecoder(req.Body).Decode(&body); err != nil || len(body.Messages) == 0 {
						t.Error("invalid inference request", err)
						w.WriteHeader(http.StatusBadRequest)
						return
					}
					received = body.Messages[len(body.Messages)-1].Content
					temperature := body.Temperature
					if provider == "ollama" {
						temperature = body.Options.Temperature
						if body.Options.Context != 32768 || body.Options.Tokens != scenario.tokens {
							t.Errorf("incorrect context or generation capacity: %+v", body.Options)
						}
					} else if body.MaxTokens != scenario.tokens {
						t.Errorf("incorrect external generation capacity: %d", body.MaxTokens)
					}
					if temperature != 0.2 {
						t.Errorf("invoice temperature: %v", temperature)
					}
					message := map[string]string{"content": content}
					if provider == "ollama" {
						_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": message})
					} else {
						_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": message}}})
					}
				}))
				defer server.Close()
				remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
				if err != nil {
					t.Fatal(err)
				}
				defer remote.Close()
				if result, err := remote.Generate(t.Context(), provider, "model", server.URL, "", "Invoice task", `{}`, text, scenario.tokens, 0.2, false, false, 32768); err != nil || result != content {
					t.Fatalf("model response was rejected or altered: %v", err)
				}
				expected := text
				if provider == "ollama" {
					expected = "Invoice task\nRequired JSON schema:\n{}\nBEGIN OCR DOCUMENT\n" + text + "\nEND OCR DOCUMENT"
				}
				if received != expected {
					t.Fatalf("provider input was altered: received %d bytes, expected %d", len(received), len(expected))
				}
			})
		}
	}
}

func TestExternalAuthenticationAndInvalidOutputs(t *testing.T) {
	for _, tc := range []struct {
		name, content, finish string
		status                int
		bad, retry            bool
	}{
		{"valid", properties, "stop", 200, false, false},
		{"empty object", `{}`, "stop", 200, true, false},
		{"missing properties", `{"description":"summary"}`, "stop", 200, true, false},
		{"null properties", `{"description":null,"tags":null,"sender":null,"recipients":null,"documentDate":null,"subject":null}`, "stop", 200, false, false},
		{"empty properties", `{"description":"","tags":[],"sender":"","recipients":[],"documentDate":"","subject":""}`, "stop", 200, false, false},
		{"unknown field", `{"title":"do not overwrite"}`, "stop", 200, true, false},
		{"trailing object", properties + `{}`, "stop", 200, true, false},
		{"array", `[]`, "stop", 200, true, false},
		{"null", `null`, "stop", 200, true, false},
		{"truncated", properties, "length", 200, true, false},
		{"too large", strings.Repeat("x", 65537), "stop", 200, true, false},
		{"unauthorized", "SECRET response", "", 401, true, false},
		{"busy", "SECRET response", "", 429, true, true},
		{"unavailable", "SECRET response", "", 503, true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if req.URL.Path != "/custom/v1/chat/completions" || req.Header.Get("Authorization") != "Bearer secret" {
					t.Error("wrong endpoint or credential")
				}
				w.WriteHeader(tc.status)
				_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": tc.finish, "message": map[string]string{"content": tc.content}}}})
			}))
			defer server.Close()
			r, _ := NewDocumentPropertyRemoteDataSource(server.URL)
			defer r.Close()
			_, err := r.Extract(t.Context(), "openai", "model", server.URL+"/custom/v1/", "secret", "OCR text", false, false)
			if (err != nil) != tc.bad {
				t.Fatal(err)
			}
			if err != nil {
				if tc.status == 429 || tc.status == 503 {
					if !errors.Is(err, m.ErrOverloaded) {
						t.Fatalf("provider overload did not receive backpressure: %v", err)
					}
					return
				}
				var failure m.DocumentProcessingError
				if !errors.As(err, &failure) || failure.Retryable != tc.retry || strings.Contains(err.Error(), "SECRET") {
					t.Fatal("unsafe failure", err)
				}
			}
		})
	}
}

func TestRedirectNeverForwardsCredentialsOrDocumentText(t *testing.T) {
	forwarded := false
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { forwarded = true }))
	defer target.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, 307) }))
	defer server.Close()
	r, _ := NewDocumentPropertyRemoteDataSource(server.URL)
	defer r.Close()
	if _, err := r.Extract(t.Context(), "openai", "model", server.URL, "secret", "private OCR", false, false); err == nil || forwarded {
		t.Fatal("redirect was followed")
	}
}

func TestEmptyEffectivePrefixSkipsPropertyInference(t *testing.T) {
	remote, err := NewDocumentPropertyRemoteDataSource("http://127.0.0.1:1")
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	for _, text := range []string{"", " \n\t", strings.Repeat(" ", 100000) + "later content"} {
		result, err := remote.Extract(t.Context(), "ollama", "model", "", "", text, false, false)
		if err != nil || result.Description != "" {
			t.Fatalf("empty prefix: %+v %v", result, err)
		}
	}
}
