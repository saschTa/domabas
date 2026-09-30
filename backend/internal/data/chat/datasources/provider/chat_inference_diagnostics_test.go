package provider

import (
	"bytes"
	"encoding/json"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestChatThinkingDefaultDiagnosticsAndOutputLimit(t *testing.T) {
	for _, finish := range []string{"stop", "length"} {
		t.Run(finish, func(t *testing.T) {
			var logs bytes.Buffer
			s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/show" {
					_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":65536},"thinking":{"values":[true,false],"default":false}}`))
					return
				}
				var request map[string]any
				if json.NewDecoder(r.Body).Decode(&request) != nil {
					t.Error("invalid request")
				}
				options := request["options"].(map[string]any)
				if request["think"] != false || options["num_predict"] != float64(2048) {
					t.Errorf("thinking must be disabled without a reasoning allowance: %v", options)
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": finish, "message": map[string]string{"thinking": "SECRET_REASONING", "content": `{"action":"answer","content":"SECRET_ANSWER","query":"","documentId":"","offset":0}`}, "prompt_eval_count": 123, "eval_count": 456})
			}))
			defer s.Close()
			remote, _ := NewChatProviderRemoteDataSource(s.URL, slog.New(slog.NewJSONHandler(&logs, nil)))
			defer remote.Close()
			input := chatInferenceFixture("ollama", s.URL)
			input.Messages = []m.ChatProviderMessage{{Role: "user", Content: "SECRET_QUESTION"}}
			_, err := remote.Generate(t.Context(), input)
			if finish == "length" {
				var failure m.ChatProcessingError
				if !errors.As(err, &failure) || failure.Code != "output_limit" {
					t.Fatalf("wrong output error: %v", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(logs.String(), "SECRET") || !strings.Contains(logs.String(), `"generated_tokens":456`) || !strings.Contains(logs.String(), `"thinking_requested":false`) {
				t.Fatalf("unsafe or absent diagnostics: %s", logs.String())
			}
		})
	}
}
