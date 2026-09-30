package llm

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestDocumentRequestsUseRequestedContextAndExactModelMaximum(t *testing.T) {
	for _, scenario := range []struct {
		name                         string
		requested, maximum, expected int
	}{
		{"legacy", 0, 131072, 16384},
		{"default", m.DefaultDocumentContextLength, 131072, 32768},
		{"smaller request", 8192, 131072, 8192},
		{"model cap", 131072, 65536, 65536},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			chats := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				var body map[string]any
				if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
					t.Error(err)
				}
				if body["model"] != "org/model:tag" {
					t.Error("lookup or inference changed the model")
				}
				if req.URL.Path == "/api/show" {
					_ = json.NewEncoder(w).Encode(map[string]any{"model_info": map[string]any{"general.architecture": "qwen35", "qwen35.context_length": scenario.maximum, "vision.context_length": 4096}})
					return
				}
				chats++
				options, ok := body["options"].(map[string]any)
				if req.URL.Path != "/api/chat" || !ok || options["num_ctx"] != float64(scenario.expected) || options["num_predict"] != float64(2048) {
					t.Errorf("wrong inference options: %v", body)
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"content": properties}})
			}))
			defer server.Close()
			remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			maximum, err := remote.ModelContext(t.Context(), "org/model:tag")
			if err != nil || maximum != scenario.maximum || chats != 0 {
				t.Fatalf("read-only lookup: %d %v", maximum, err)
			}
			if _, err = remote.Extract(t.Context(), "ollama", "org/model:tag", "", "", "Example", false, false, scenario.requested); err != nil || chats != 1 {
				t.Fatalf("context request: %v, chats %d", err, chats)
			}
		})
	}
}

func TestDocumentUnknownModelMaximumStopsBeforeInference(t *testing.T) {
	for _, metadata := range []string{
		`{}`,
		`{"model_info":{"qwen35.context_length":131072}}`,
		`{"model_info":{"general.architecture":"qwen35","vision.context_length":131072}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":0}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":-1}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":8192.5}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":"131072"}}`,
		`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":2147483648}}`,
	} {
		t.Run(metadata, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if req.URL.Path != "/api/show" {
					t.Error("unknown maximum reached generation or model pull")
				}
				_, _ = w.Write([]byte(metadata))
			}))
			defer server.Close()
			remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			_, err = remote.Extract(t.Context(), "ollama", "model", "", "", "Example", false, false, 32768)
			var failure m.DocumentProcessingError
			if !errors.As(err, &failure) || failure.Code != "configuration_unavailable" {
				t.Fatalf("wrong failure: %v", err)
			}
		})
	}
}

func TestDocumentModelLookupDoesNotPullMissingModel(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path != "/api/show" {
			t.Error("lookup pulled model")
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()
	remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	if _, err := remote.ModelContext(t.Context(), "missing"); err == nil {
		t.Fatal("missing model has a maximum")
	}
}
