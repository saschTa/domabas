//go:build e2e

package e2e_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
)

func TestIndependentModelContextSettingsReachChatPropertiesAndInvoices(t *testing.T) {
	databaseURL := testdb.New(t)
	env := newServerEnvironment(t, databaseURL)
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	contexts := map[string][]int{}
	ollama := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Model   string `json:"model"`
			Options struct {
				Context int `json:"num_ctx"`
			} `json:"options"`
			Messages []struct {
				Content string `json:"content"`
			} `json:"messages"`
		}
		if json.NewDecoder(r.Body).Decode(&request) != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		switch r.URL.Path {
		case "/api/show":
			if request.Model == "unknown-context" {
				_, _ = w.Write([]byte(`{"model_info":{}}`))
				return
			}
			_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":65536}}`))
		case "/api/chat":
			kind := "properties"
			content := `{"description":"Context fixture","tags":[],"sender":"","recipients":[],"documentDate":"","subject":""}`
			if request.Model == "chat-context" {
				kind = "chat"
				content = `{"action":"answer","content":"Context verified.","query":"","documentId":"","offset":0}`
			} else if len(request.Messages) > 0 && strings.Contains(request.Messages[0].Content, `"required":["reason"]`) {
				kind = "invoice"
				content = `{"reason":"other_document"}`
			}
			mu.Lock()
			contexts[kind] = append(contexts[kind], request.Options.Context)
			mu.Unlock()
			_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"role": "assistant", "content": content}})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer ollama.Close()
	env = append(env, "LLM_OLLAMA_URL="+ollama.URL)
	base, stop := startServer(t, binary, databaseURL, env)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	admin := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Context library","email":"context-admin@example.test","password":"Context test password 2026!"}`, 201, "AuthSession")["token"].(string)
	owner := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Context owner","email":"context-owner@example.test","password":"Context test password 2026!"}`, 201, "AuthSession")["token"].(string)
	for _, path := range []string{"/api/v1/system/chat/model-context", "/api/v1/system/document-processing/model-context"} {
		api.request(owner, "GET", path+"?model=chat-context", "", 403, "Error")
		limit := api.request(admin, "GET", path+"?model=org%2Fmodel:tag", "", 200, "OllamaModelContext")
		if limit["model"] != "org/model:tag" || limit["maxContextLength"] != float64(65536) {
			t.Fatal("incorrect model metadata", limit)
		}
		for _, query := range []string{"", "?model=", "?model=a&model=b", "?model=a&extra=b"} {
			api.request(admin, "GET", path+query, "", 400, "Error")
		}
		api.request(admin, "GET", path+"?model=unknown-context", "", 503, "Error")
	}
	chatPath, pipelinePath := "/api/v1/system/chat/configuration", "/api/v1/system/document-processing"
	chat := api.request(admin, "GET", chatPath, "", 200, "ChatConfiguration")
	pipeline := api.request(admin, "GET", pipelinePath, "", 200, "DocumentProcessingConfiguration")
	if chat["contextLength"] != float64(32768) || pipeline["llm"].(map[string]any)["contextLength"] != float64(32768) {
		t.Fatal("context defaults", chat, pipeline)
	}
	for _, invalid := range []string{"0", "1023", "1048577", "32768.5", "null", `"32768"`} {
		api.request(admin, "PUT", chatPath, fmt.Sprintf(`{"expectedRevision":%.0f,"enabled":true,"provider":"ollama","model":"chat-context","baseUrl":"","contextLength":%s}`, chat["revision"], invalid), 400, "Error")
		api.request(admin, "PUT", pipelinePath, fmt.Sprintf(`{"expectedRevision":%.0f,"language":%q,"segmentation":%q,"llm":{"enabled":true,"provider":"ollama","model":"pipeline-context","baseUrl":"","contextLength":%s}}`, pipeline["revision"], pipeline["language"], pipeline["segmentation"], invalid), 400, "Error")
	}
	chat = api.request(admin, "PUT", chatPath, fmt.Sprintf(`{"expectedRevision":%.0f,"enabled":true,"provider":"ollama","model":"chat-context","baseUrl":"","contextLength":131072}`, chat["revision"]), 200, "ChatConfiguration")
	pipeline = api.request(admin, "PUT", pipelinePath, fmt.Sprintf(`{"expectedRevision":%.0f,"language":%q,"segmentation":%q,"llm":{"enabled":true,"invoiceEnabled":true,"provider":"ollama","model":"pipeline-context","baseUrl":"","contextLength":16384}}`, pipeline["revision"], pipeline["language"], pipeline["segmentation"]), 200, "DocumentProcessingConfiguration")
	chatRevision, pipelineRevision := chat["revision"], pipeline["revision"]
	chat = api.request(admin, "PUT", chatPath, fmt.Sprintf(`{"expectedRevision":%.0f,"enabled":true,"provider":"ollama","model":"chat-context","baseUrl":""}`, chatRevision), 200, "ChatConfiguration")
	pipeline = api.request(admin, "PUT", pipelinePath, fmt.Sprintf(`{"expectedRevision":%.0f,"language":%q,"segmentation":%q,"llm":{"enabled":true,"invoiceEnabled":true,"provider":"ollama","model":"pipeline-context","baseUrl":""}}`, pipelineRevision, pipeline["language"], pipeline["segmentation"]), 200, "DocumentProcessingConfiguration")
	if chat["revision"] != chatRevision || pipeline["revision"] != pipelineRevision {
		t.Fatal("omitted context changed configuration")
	}
	stop()
	base, stop = startServer(t, binary, databaseURL, env)
	api.baseURL = base
	chat = api.request(admin, "GET", chatPath, "", 200, "ChatConfiguration")
	pipeline = api.request(admin, "GET", pipelinePath, "", 200, "DocumentProcessingConfiguration")
	if chat["contextLength"] != float64(131072) || pipeline["llm"].(map[string]any)["contextLength"] != float64(16384) {
		t.Fatal("independent contexts did not survive restart", chat, pipeline)
	}
	conversation := api.request(admin, "POST", "/api/v1/chat/conversations", fmt.Sprintf(`{"requestId":%q}`, uuid.NewString()), 201, "ChatConversation")
	path := "/api/v1/chat/conversations/" + conversation["id"].(string)
	turn := api.request(admin, "POST", path+"/messages", fmt.Sprintf(`{"requestId":%q,"content":"Verify the context setting."}`, uuid.NewString()), 202, "ChatAcceptedTurn")["assistantMessage"].(map[string]any)
	api.waitChat(admin, path, turn["turnId"].(string), "completed", "")
	document := api.upload(admin, "context.pdf", fixtures.PDF(t, fixtures.Page{Text: "Context setting verification document"}), `{"title":"Context verification"}`, true, 202)
	id := document["id"].(string)
	deadline := time.Now().Add(3 * time.Minute)
	for {
		processing := api.request(admin, "GET", "/api/v1/documents/"+id+"/processing", "", 200, "DocumentProcessing")
		if processing["state"] == "ready" {
			break
		}
		if processing["state"] == "failed" || time.Now().After(deadline) {
			t.Fatalf("ingestion failed: %v", processing)
		}
		time.Sleep(100 * time.Millisecond)
	}
	api.waitAI(admin, id, "succeeded")
	mu.Lock()
	defer mu.Unlock()
	for kind, expected := range map[string]int{"chat": 65536, "properties": 16384, "invoice": 16384} {
		if len(contexts[kind]) == 0 {
			t.Fatalf("missing %s request", kind)
		}
		for _, actual := range contexts[kind] {
			if actual != expected {
				t.Fatalf("%s context = %d, want %d", kind, actual, expected)
			}
		}
	}
}
