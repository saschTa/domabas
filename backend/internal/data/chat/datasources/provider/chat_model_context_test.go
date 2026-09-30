package provider

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"reflect"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

const chatModelContextFixture = `{"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`

func TestChatRequestedContextIsSentAndCappedByTheSelectedArchitecture(t *testing.T) {
	for _, test := range []struct {
		requested, maximum, effective int
	}{
		{0, 131072, 32768},
		{32768, 131072, 32768},
		{65536, 131072, 65536},
		{32768, 8192, 8192},
		{1048576, 131072, 131072},
		{16384, 131072, 16384},
	} {
		t.Run(fmt.Sprintf("%d/%d", test.requested, test.maximum), func(t *testing.T) {
			var paths []string
			provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				paths = append(paths, r.URL.Path)
				if r.URL.Path == "/api/show" {
					fmt.Fprintf(w, `{"parameters":"num_ctx 4096","model_info":{"general.architecture":"qwen35","vision.context_length":2048,"qwen35.context_length":%d}}`, test.maximum)
					return
				}
				var request struct {
					Options struct {
						Context int `json:"num_ctx"`
						Output  int `json:"num_predict"`
					} `json:"options"`
				}
				if err := json.NewDecoder(r.Body).Decode(&request); err != nil || request.Options.Context != test.effective || request.Options.Output != 2048 {
					t.Errorf("unexpected request %+v: %v", request, err)
				}
				fmt.Fprint(w, `{"done":true,"done_reason":"stop","message":{"content":"{\"action\":\"answer\",\"content\":\"Done\",\"query\":\"\",\"documentId\":\"\",\"offset\":0}"}}`)
			})
			input := chatInferenceFixture("ollama", "")
			input.Configuration.ContextLength = test.requested
			if _, err := provider.Generate(t.Context(), input); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(paths, []string{"/api/show", "/api/chat"}) {
				t.Fatal(paths)
			}
		})
	}
}

func TestChatModelContextRejectsUnavailableMaximumBeforeInference(t *testing.T) {
	for _, metadata := range []string{
		`{}`, `{"model_info":{}}`, `{"model_info":null}`,
		`{"model_info":{"general.architecture":"qwen35","vision.context_length":131072}}`,
		`{"model_info":{"qwen35.context_length":131072}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":null}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":0}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":-1024}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":1024.5}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":"32768"}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":2147483648}}`,
	} {
		t.Run(metadata, func(t *testing.T) {
			provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/api/show" {
					t.Error("inference attempted without model maximum", r.URL.Path)
				}
				fmt.Fprint(w, metadata)
			})
			_, err := provider.Generate(t.Context(), chatInferenceFixture("ollama", ""))
			var failure m.ChatProcessingError
			if !errors.As(err, &failure) || failure.Code != "configuration_unavailable" || failure.Retryable {
				t.Fatal(err)
			}
		})
	}
}

func TestChatModelContextLookupIsReadOnly(t *testing.T) {
	for _, missing := range []bool{false, true} {
		t.Run(fmt.Sprint(missing), func(t *testing.T) {
			provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/api/show" || r.Method != http.MethodPost {
					t.Error("unexpected lookup request", r.Method, r.URL.Path)
				}
				var request map[string]string
				if err := json.NewDecoder(r.Body).Decode(&request); err != nil || request["model"] != "library/qwen3.5:4b" {
					t.Error(request, err)
				}
				if missing {
					w.WriteHeader(http.StatusNotFound)
					fmt.Fprint(w, "private provider body")
					return
				}
				fmt.Fprint(w, chatModelContextFixture)
			})
			result, err := provider.ModelContext(t.Context(), "library/qwen3.5:4b")
			if missing {
				if !errors.Is(err, errChatModelMissing) {
					t.Fatal(err)
				}
			} else if err != nil || result.Model != "library/qwen3.5:4b" || result.MaxContextLength != 131072 {
				t.Fatal(result, err)
			}
		})
	}
}

func TestChatPullRepeatsModelDiscoveryBeforeInference(t *testing.T) {
	for _, valid := range []bool{false, true} {
		t.Run(fmt.Sprint(valid), func(t *testing.T) {
			var paths []string
			provider, _ := chatProviderFixture(t, func(w http.ResponseWriter, r *http.Request) {
				paths = append(paths, r.URL.Path)
				switch len(paths) {
				case 1:
					w.WriteHeader(http.StatusNotFound)
				case 2:
					fmt.Fprint(w, `{"status":"success"}`)
				case 3:
					if valid {
						fmt.Fprint(w, chatModelContextFixture)
					} else {
						fmt.Fprint(w, `{}`)
					}
				case 4:
					fmt.Fprint(w, `{"done":true,"done_reason":"stop","message":{"content":"{\"action\":\"answer\",\"content\":\"Done\",\"query\":\"\",\"documentId\":\"\",\"offset\":0}"}}`)
				default:
					t.Error("unexpected request", r.URL.Path)
				}
			})
			_, err := provider.Generate(t.Context(), chatInferenceFixture("ollama", ""))
			expected := []string{"/api/show", "/api/pull", "/api/show"}
			if valid {
				expected = append(expected, "/api/chat")
				if err != nil {
					t.Fatal(err)
				}
			} else {
				var failure m.ChatProcessingError
				if !errors.As(err, &failure) || failure.Code != "configuration_unavailable" {
					t.Fatal(err)
				}
			}
			if !reflect.DeepEqual(paths, expected) {
				t.Fatal(paths)
			}
		})
	}
}
