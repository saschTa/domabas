package provider

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestChatThinkingRequests(t *testing.T) {
	for _, kind := range []string{"ollama", "openai"} {
		for _, thinking := range []bool{false, true} {
			for _, answerOnly := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/thinking=%t/answer=%t", kind, thinking, answerOnly), func(t *testing.T) {
					calls := 0
					server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
						if r.URL.Path == "/api/show" {
							_, _ = w.Write([]byte(chatModelContextFixture))
							return
						}
						calls++
						var payload map[string]any
						if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
							t.Error(err)
							return
						}
						budget := 2048
						if thinking {
							budget += 4096
						}
						if kind == "ollama" {
							if payload["think"] != thinking || payload["options"].(map[string]any)["num_predict"] != float64(budget) || payload["reasoning_effort"] != nil {
								t.Errorf("wrong native thinking request: %v", payload)
							}
							_, _ = w.Write([]byte(`{"done":true,"done_reason":"stop","message":{"thinking":"private reasoning","content":"{\"action\":\"answer\",\"content\":\"Final answer\",\"query\":\"\",\"documentId\":\"\",\"offset\":0}"}}`))
						} else {
							effort := "none"
							if thinking {
								effort = "medium"
							}
							if payload["reasoning_effort"] != effort || payload["max_tokens"] != float64(budget) || payload["think"] != nil {
								t.Errorf("wrong external thinking request: %v", payload)
							}
							_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"stop","message":{"reasoning_content":"private reasoning","content":"Final answer"}}]}`))
						}
					}))
					defer server.Close()
					remote, err := NewChatProviderRemoteDataSource(server.URL)
					if err != nil {
						t.Fatal(err)
					}
					input := chatInferenceFixture(kind, server.URL)
					input.Configuration.ThinkingEnabled = thinking
					input.AnswerOnly = answerOnly
					got, err := remote.Generate(t.Context(), input)
					if err != nil || got.Content != "Final answer" || calls != 1 {
						t.Fatalf("thinking request failed or leaked reasoning: %+v %v (%d calls)", got, err, calls)
					}
				})
			}
		}
	}
}
