//go:build e2e

package e2e_test

import (
	"context"
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
	"github.com/jackc/pgx/v5"
)

func TestDocumentAISettingsCanChangeDuringActiveInference(t *testing.T) {
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
	type inference struct {
		model   string
		context int
		invoice bool
	}
	entered := make(chan inference, 32)
	resume := make(chan struct{})
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(resume) }) }
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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
			_, _ = w.Write([]byte(`{"model_info":{"general.architecture":"qwen35","qwen35.context_length":65536}}`))
		case "/api/chat":
			call := inference{model: request.Model, context: request.Options.Context}
			for _, message := range request.Messages {
				call.invoice = call.invoice || strings.Contains(message.Content, `"required":["reason"]`)
			}
			select {
			case entered <- call:
			case <-r.Context().Done():
				return
			}
			select {
			case <-resume:
			case <-r.Context().Done():
				return
			}
			content := `{"description":"Active settings verified","tags":[],"sender":"","recipients":[],"documentDate":"","subject":""}`
			if call.invoice {
				content = `{"reason":"other_document"}`
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"done": true, "done_reason": "stop", "message": map[string]string{"role": "assistant", "content": content}})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer func() { release(); provider.Close() }()
	env = append(env, "LLM_OLLAMA_URL="+provider.URL)
	base, stop := startServer(t, binary, databaseURL, env)
	defer func() { release(); stop() }()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 10 * time.Second}, spec: spec}
	admin := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Active settings","email":"active-settings@example.test","password":"Active settings password 2026!"}`, 201, "AuthSession")["token"].(string)
	const path = "/api/v1/system/document-processing"
	configuration := api.request(admin, "GET", path, "", 200, "DocumentProcessingConfiguration")
	body := func(revision any, model string, context int, invoice bool) string {
		return fmt.Sprintf(`{"expectedRevision":%.0f,"language":%q,"segmentation":%q,"llm":{"enabled":true,"invoiceEnabled":%t,"provider":"ollama","model":%q,"baseUrl":"","contextLength":%d}}`, revision, configuration["language"], configuration["segmentation"], invoice, model, context)
	}
	configuration = api.request(admin, "PUT", path, body(configuration["revision"], "settings-original", 16384, true), 200, "DocumentProcessingConfiguration")
	document := api.upload(admin, "active-settings.pdf", fixtures.PDF(t, fixtures.Page{Text: "An ordinary document for testing active AI settings"}), `{"title":"Active settings document"}`, true, 202)
	id := document["id"].(string)
	ingestion := api.waitProcessing(admin, id, "ready")
	waitInference := func(expected inference) {
		t.Helper()
		timer := time.NewTimer(90 * time.Second)
		defer timer.Stop()
		for {
			select {
			case call := <-entered:
				if call == expected {
					return
				}
			case <-timer.C:
				t.Fatalf("inference did not start with configuration %+v", expected)
			}
		}
	}
	waitInference(inference{"settings-original", 16384, true})
	for _, next := range []inference{
		{"settings-updated", 16384, true},
		{"settings-updated", 32768, true},
		{"settings-updated", 32768, false},
		{"settings-updated", 32768, true},
	} {
		previousRevision := configuration["revision"]
		configuration = api.request(admin, "PUT", path, body(previousRevision, next.model, next.context, next.invoice), 200, "DocumentProcessingConfiguration")
		if configuration["revision"].(float64) <= previousRevision.(float64) || configuration["automaticBatchId"] != nil {
			t.Fatal("AI settings did not advance independently of ingestion", configuration)
		}
		retained := api.request(admin, "GET", path, "", 200, "DocumentProcessingConfiguration")
		llm := retained["llm"].(map[string]any)
		if retained["revision"] != configuration["revision"] || llm["model"] != next.model || llm["contextLength"] != float64(next.context) || llm["invoiceEnabled"] != next.invoice || llm["enabled"] != true {
			t.Fatal("active AI configuration was not persisted", retained)
		}
		api.request(admin, "PUT", path, body(previousRevision, "stale-model", 16384, false), 409, "Error")
		processing := api.request(admin, "GET", "/api/v1/documents/"+id+"/processing", "", 200, "DocumentProcessing")
		if processing["state"] != "ready" || processing["generation"] != ingestion["generation"] {
			t.Fatal("AI settings reran or blocked searchable ingestion", processing)
		}
		waitInference(next)
	}
	release()
	completed := api.waitAI(admin, id, "succeeded")
	if completed["configurationRevision"] != configuration["revision"] {
		t.Fatal("AI completed under an obsolete configuration", completed)
	}
	final := api.request(admin, "GET", "/api/v1/documents/"+id, "", 200, "Document")
	if final["description"] != "Active settings verified" {
		t.Fatal("latest AI attempt did not publish", final)
	}
	verifyAISettingsDuringSchedulerTransaction(api, admin, databaseURL, id, configuration)
}

func verifyAISettingsDuringSchedulerTransaction(api *ingestionAPI, admin, databaseURL, documentID string, configuration map[string]any) {
	t := api.t
	t.Helper()
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	observer, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer observer.Close(context.Background())
	if _, err = connection.Exec(t.Context(), `CREATE FUNCTION pause_settings_admission() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':api-settings-admission',0)); RETURN NULL; END $$`); err != nil {
		t.Fatal(err)
	}
	if _, err = connection.Exec(t.Context(), "CREATE TRIGGER pause_settings_admission BEFORE DELETE ON scheduler_requests FOR EACH STATEMENT EXECUTE FUNCTION pause_settings_admission()"); err != nil {
		t.Fatal(err)
	}
	blocker, err := connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err = blocker.Exec(t.Context(), `SELECT pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':api-settings-admission',0))`); err != nil {
		t.Fatal(err)
	}
	api.request(admin, "POST", "/api/v1/documents/"+documentID+"/ai/retry", fmt.Sprintf(`{"requestId":%q,"configurationRevision":%.0f}`, uuid.NewString(), configuration["revision"]), 202, "DocumentAIProcessing")
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	for {
		var paused bool
		if err = observer.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity a WHERE a.wait_event_type='Lock' AND $1::integer=ANY(pg_blocking_pids(a.pid)))`, int(connection.PgConn().PID())).Scan(&paused); err != nil {
			t.Fatal(err)
		}
		if paused {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(25 * time.Millisecond):
		}
	}
	bounded := *api
	bounded.client = &http.Client{Timeout: 2 * time.Second}
	const path = "/api/v1/system/document-processing"
	for _, enabled := range []bool{true, false} {
		body := fmt.Sprintf(`{"expectedRevision":%.0f,"language":%q,"segmentation":%q,"llm":{"enabled":%t,"invoiceEnabled":%t,"provider":"ollama","model":"scheduler-settings","baseUrl":"","contextLength":65536}}`, configuration["revision"], configuration["language"], configuration["segmentation"], enabled, enabled)
		configuration = bounded.request(admin, "PUT", path, body, 200, "DocumentProcessingConfiguration")
		stored := bounded.request(admin, "GET", path, "", 200, "DocumentProcessingConfiguration")
		llm := stored["llm"].(map[string]any)
		if stored["revision"] != configuration["revision"] || llm["enabled"] != enabled || llm["invoiceEnabled"] != enabled || llm["model"] != "scheduler-settings" || llm["contextLength"] != float64(65536) {
			t.Fatal("settings failed to persist during scheduler transaction", stored)
		}
	}
	if err = blocker.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	settled := api.waitAI(admin, documentID, "skipped")
	if settled["configurationRevision"] != configuration["revision"] {
		t.Fatal("maintenance did not adopt the saved settings after admission resumed", settled)
	}
}
