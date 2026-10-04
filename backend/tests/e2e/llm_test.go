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
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
)

func TestIssue27OptionalPropertiesAdminAuthorityAndDurableProcessing(t *testing.T) {
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
	var calls atomic.Int32
	var fail atomic.Bool
	var hold atomic.Bool
	blocked := make(chan struct{}, 1)
	yielded := make(chan struct{}, 1)
	resume := make(chan struct{})
	var resumeOnce sync.Once
	release := func() { resumeOnce.Do(func() { close(resume) }) }
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer private-api-key" {
			w.WriteHeader(401)
			return
		}
		calls.Add(1)
		var body map[string]any
		if json.NewDecoder(r.Body).Decode(&body) != nil || body["model"] != "test-model" || body["reasoning_effort"] != "medium" {
			w.WriteHeader(400)
			return
		}
		format, _ := body["response_format"].(map[string]any)
		schema, _ := format["json_schema"].(map[string]any)
		definition, _ := schema["schema"].(map[string]any)
		if format["type"] != "json_schema" || definition["type"] != "object" {
			w.WriteHeader(400)
			_, _ = w.Write([]byte(`{"error":"'response_format.type' must be 'json_schema' or 'text'"}`))
			return
		}
		if hold.Load() {
			select {
			case blocked <- struct{}{}:
			default:
			}
			select {
			case <-resume:
			case <-r.Context().Done():
				select {
				case yielded <- struct{}{}:
				default:
				}
				return
			}
		}
		if fail.Load() {
			w.WriteHeader(401)
			_, _ = w.Write([]byte("PRIVATE provider details"))
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": map[string]string{"content": `{"description":"AI summary","sender":"LLM fixture sender","subject":"LLM fixture subject","tags":["llm-extracted"],"recipients":null,"documentDate":"2026-09-19"}`}}}})
	}))
	defer func() {
		release()
		provider.Close()
	}()
	base, stop := startServer(t, binary, databaseURL, env)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	admin := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"LLM tests","email":"llm-admin@example.test","password":"LLM tests password 2026!"}`, 201, "AuthSession")["token"].(string)
	user := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Other library","email":"llm-user@example.test","password":"LLM tests password 2026!"}`, 201, "AuthSession")["token"].(string)
	path := "/api/v1/system/document-processing"
	api.request(user, "GET", path, "", 403, "Error")
	api.request(user, "PUT", path, "{", 403, "Error")
	configuration := api.request(admin, "GET", path, "", 200, "DocumentProcessingConfiguration")
	llm := configuration["llm"].(map[string]any)
	if llm["enabled"] != false || llm["model"] != "qwen3.5:4b" || llm["credentialConfigured"] != false || llm["lmStudioCompatibility"] != false || llm["propertyThinkingEnabled"] != false || llm["invoiceThinkingEnabled"] != false {
		t.Fatal("wrong defaults", llm)
	}
	for _, invalid := range []string{`null`, `{}`, `{"enabled":true,"provider":"openai","model":"fixture","baseUrl":"http://localhost/v1","apiKey":null}`, `{"enabled":true,"enabled":false,"provider":"ollama","model":"fixture","baseUrl":""}`, `{"enabled":true,"provider":"ollama","model":"fixture","baseUrl":"","credentialConfigured":true}`} {
		api.request(admin, "PUT", path, `{"language":"eng+deu","segmentation":"auto","llm":`+invalid+`}`, 400, "Error")
	}
	body := fmt.Sprintf(`{"language":"eng+deu","segmentation":"auto","expectedRevision":%.0f,"llm":{"enabled":true,"provider":"openai","model":"test-model","baseUrl":%q,"apiKey":"private-api-key","lmStudioCompatibility":true,"propertyThinkingEnabled":true,"invoiceThinkingEnabled":false}}`, configuration["revision"], provider.URL+"/v1")
	configured := api.request(admin, "PUT", path, body, 200, "DocumentProcessingConfiguration")
	if calls.Load() != 0 {
		t.Fatal("saving settings performed inference")
	}
	encoded, _ := json.Marshal(configured)
	if strings.Contains(string(encoded), "private-api-key") || !configured["llm"].(map[string]any)["credentialConfigured"].(bool) {
		t.Fatal("unsafe credential response")
	}
	stop()
	base, stop = startServer(t, binary, databaseURL, env)
	api.baseURL = base
	retained := api.request(admin, "GET", path, "", 200, "DocumentProcessingConfiguration")
	if retained["revision"] != configured["revision"] || retained["llm"].(map[string]any)["enabled"] != true || retained["llm"].(map[string]any)["lmStudioCompatibility"] != true || retained["llm"].(map[string]any)["propertyThinkingEnabled"] != true || retained["llm"].(map[string]any)["invoiceThinkingEnabled"] != false {
		t.Fatal("settings did not survive restart")
	}
	doc := api.upload(user, "llm.png", fixtures.PNG(t, "LLM properties invoice 2026"), `{"title":"Human title","description":"Human summary"}`, true, 202)
	id := doc["id"].(string)
	api.waitProcessing(user, id, "ready")
	api.waitAI(user, id, "succeeded")
	got := api.request(user, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	if got["sender"] != "LLM fixture sender" || got["subject"] != "LLM fixture subject" || got["description"] != "Human summary" || got["title"] != "Human title" || got["documentDate"] != "2026-09-19" {
		t.Fatal("unexpected extracted properties", got)
	}
	if recipients := got["recipients"].([]any); len(recipients) != 0 {
		t.Fatal("unknown recipients became populated metadata", recipients)
	}
	jobs := api.request(user, "GET", "/api/v1/document-jobs?pipeline=ai&documentId="+id, "", 200, "DocumentJobPage")
	snapshot := jobs["items"].([]any)[0].(map[string]any)["configuration"].(map[string]any)
	if snapshot["propertyExtractionEnabled"] != true || snapshot["propertyExtractionModel"] != "test-model" {
		t.Fatal("job lost its extraction identity", snapshot)
	}
	encoded, _ = json.Marshal(snapshot)
	if strings.Contains(string(encoded), provider.URL) || strings.Contains(string(encoded), "private-api-key") {
		t.Fatal("namespace history disclosed provider settings")
	}
	search := api.request(user, "POST", "/api/v1/documents/search", `{"query":"","mode":"fulltext","tags":["llm-extracted"]}`, 200, "DocumentSearchResults")
	if search["total"] != float64(1) {
		t.Fatal("extracted properties not searchable")
	}
	fail.Store(true)
	failed := api.upload(user, "failed.png", fixtures.PNG(t, "LLM failure fixture different bytes"), `{"title":"Retry me"}`, true, 202)
	failedID := failed["id"].(string)
	processing := api.waitProcessing(user, failedID, "ready")
	failedAI := api.waitAI(user, failedID, "failed")
	if failedAI["failureCode"] != "inference_unavailable" || processing["failureCode"] != nil {
		t.Fatal("AI failure was not isolated and sanitized", processing, failedAI)
	}
	search = api.request(user, "POST", "/api/v1/documents/search", `{"query":"Retry me","mode":"fulltext"}`, 200, "DocumentSearchResults")
	if search["total"] != float64(1) {
		t.Fatal("AI failure removed the document from search", search)
	}
	ingestionJobs := api.request(user, "GET", "/api/v1/document-jobs?pipeline=ingestion&status=succeeded&documentId="+failedID, "", 200, "DocumentJobPage")["items"].([]any)
	aiJobs := api.request(user, "GET", "/api/v1/document-jobs?pipeline=ai&status=failed&documentId="+failedID, "", 200, "DocumentJobPage")["items"].([]any)
	if len(ingestionJobs) != 1 || len(aiJobs) != 1 || aiJobs[0].(map[string]any)["id"] != failedAI["jobId"] {
		t.Fatal("pipeline filters lost the independent outcomes", ingestionJobs, aiJobs)
	}
	fail.Store(false)
	retryBody := fmt.Sprintf(`{"requestId":"e9b23183-4a37-4fe0-a449-b8aa5d774ab5","configurationRevision":%.0f}`, failedAI["configurationRevision"])
	retryPath := "/api/v1/documents/" + failedID + "/ai/retry"
	api.request(admin, "POST", retryPath, retryBody, 404, "Error")
	retried := api.request(user, "POST", retryPath, retryBody, 202, "DocumentAIProcessing")
	repeated := api.request(user, "POST", retryPath, retryBody, 202, "DocumentAIProcessing")
	if retried["jobId"] != repeated["jobId"] || retried["jobId"] == failedAI["jobId"] {
		t.Fatal("AI retry did not preserve its request identity", retried, repeated)
	}
	api.waitAI(user, failedID, "succeeded")
	afterRetry := api.waitProcessing(user, failedID, "ready")
	if afterRetry["generation"] != processing["generation"] {
		t.Fatal("AI retry reran ingestion", processing, afterRetry)
	}
	if calls.Load() < 3 {
		t.Fatal("real workflow did not call provider")
	}
	hold.Store(true)
	waiting := api.upload(user, "waiting.png", fixtures.PNG(t, "Held AI provider first document"), `{"title":"Held AI"}`, true, 202)
	waitingID := waiting["id"].(string)
	api.waitProcessing(user, waitingID, "ready")
	select {
	case <-blocked:
	case <-time.After(30 * time.Second):
		t.Fatal("AI provider was not reached")
	}
	next := api.upload(user, "next.png", fixtures.PNG(t, "Next document while AI is held"), `{"title":"Next searchable original"}`, true, 202)
	nextID := next["id"].(string)
	select {
	case <-yielded:
		t.Fatal("new ingestion cancelled an admitted external provider request")
	case <-time.After(1500 * time.Millisecond):
	}
	api.waitProcessing(user, nextID, "ready")
	waitingProcessing := api.request(user, "GET", "/api/v1/documents/"+waitingID+"/processing", "", 200, "DocumentProcessing")
	waitingAI := waitingProcessing["ai"].(map[string]any)
	if waitingAI["status"] == "failed" || waitingAI["attempt"] != float64(1) {
		t.Fatal("resource contention failed or replaced the durable attempt", waitingAI)
	}
	search = api.request(user, "POST", "/api/v1/documents/search", `{"query":"Next searchable original","mode":"fulltext"}`, 200, "DocumentSearchResults")
	if search["total"] != float64(1) {
		t.Fatal("blocked AI prevented later document search", search)
	}
	hold.Store(false)
	release()
	api.request(user, "DELETE", "/api/v1/documents/"+waitingID, "", 204, "")
	api.waitAI(user, nextID, "succeeded")
}
