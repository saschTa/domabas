package llm

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDocumentThinkingRequests(t *testing.T) {
	for _, provider := range []string{"ollama", "openai"} {
		for _, thinking := range []bool{false, true} {
			for _, compatibility := range []bool{false, true} {
				for _, tokens := range []int{256, 2048, 50000} {
					t.Run(fmt.Sprintf("%s/thinking=%t/compatibility=%t/tokens=%d", provider, thinking, compatibility, tokens), func(t *testing.T) {
						calls := 0
						server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
							if r.URL.Path == "/api/show" {
								_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":65536}}`))
								return
							}
							calls++
							var payload map[string]any
							if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
								t.Error(err)
								return
							}
							budget := tokens
							if thinking {
								budget += 4096
							}
							if provider == "ollama" {
								if payload["think"] != thinking || payload["options"].(map[string]any)["num_predict"] != float64(budget) || payload["reasoning_effort"] != nil {
									t.Errorf("wrong native thinking request: %v", payload)
								}
								_, _ = w.Write([]byte(`{"done":true,"done_reason":"stop","message":{"thinking":"private reasoning","content":"{\"reason\":\"other_document\"}"}}`))
							} else {
								effort := "none"
								if thinking {
									effort = "medium"
								}
								format := "json_object"
								if compatibility {
									format = "json_schema"
								}
								if payload["reasoning_effort"] != effort || payload["max_tokens"] != float64(budget) || payload["think"] != nil || payload["response_format"].(map[string]any)["type"] != format {
									t.Errorf("wrong external thinking request: %v", payload)
								}
								_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"stop","message":{"reasoning_content":"private reasoning","content":"{\"reason\":\"other_document\"}"}}]}`))
							}
						}))
						defer server.Close()
						remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
						if err != nil {
							t.Fatal(err)
						}
						got, err := remote.Generate(t.Context(), provider, "fixture", server.URL, "", "Task", "{}", "Synthetic text", tokens, 0.2, compatibility, thinking, 32768)
						if err != nil || got != `{"reason":"other_document"}` || calls != 1 {
							t.Fatalf("thinking request failed or leaked reasoning: %q %v (%d calls)", got, err, calls)
						}
					})
				}
			}
		}
	}
}
