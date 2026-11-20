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
	const provider = "openai"
	t.Run(provider, func(t *testing.T) {
		content := `{"description":"Consulting services.\nPayment due in 14 days.","tags":["office\tservices","invoice"],"sender":" Example Büro GmbH\r\nSample Street 1\n10115 Berlin ","recipients":["Sample Customer AG\nOther Street 2\t20095 Hamburg"],"documentDate":"2026-07-25","subject":" Invoice\r\nEXAMPLE-1001 "}`
		server := propertyResponseServer(t, provider, content)
		defer server.Close()
		remote := NewDocumentPropertyRemoteDataSource()
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
			remote := NewDocumentPropertyRemoteDataSource()
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
		message := map[string]string{"content": content}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": message}}})
	}))
}

func TestInferencePreservesSelectedInvoiceInput(t *testing.T) {
	const provider = "openai"
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
				if body.MaxTokens != scenario.tokens {
					t.Errorf("incorrect external generation capacity: %d", body.MaxTokens)
				}
				if temperature != 0.2 {
					t.Errorf("invoice temperature: %v", temperature)
				}
				message := map[string]string{"content": content}
				_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": message}}})
			}))
			defer server.Close()
			remote := NewDocumentPropertyRemoteDataSource()
			defer remote.Close()
			if result, err := remote.Generate(t.Context(), provider, "model", server.URL, "", "Invoice task", `{}`, text, scenario.tokens, 0.2, false, false, 32768); err != nil || result != content {
				t.Fatalf("model response was rejected or altered: %v", err)
			}
			expected := text
			if received != expected {
				t.Fatalf("provider input was altered: received %d bytes, expected %d", len(received), len(expected))
			}
		})
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
			r := NewDocumentPropertyRemoteDataSource()
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
	r := NewDocumentPropertyRemoteDataSource()
	defer r.Close()
	if _, err := r.Extract(t.Context(), "openai", "model", server.URL, "secret", "private OCR", false, false); err == nil || forwarded {
		t.Fatal("redirect was followed")
	}
}

func TestEmptyEffectivePrefixSkipsPropertyInference(t *testing.T) {
	remote := NewDocumentPropertyRemoteDataSource()
	defer remote.Close()
	for _, text := range []string{"", " \n\t", strings.Repeat(" ", 100000) + "later content"} {
		result, err := remote.Extract(t.Context(), "openai", "model", "https://unused.test/v1", "", text, false, false)
		if err != nil || result.Description != "" {
			t.Fatalf("empty prefix: %+v %v", result, err)
		}
	}
}
