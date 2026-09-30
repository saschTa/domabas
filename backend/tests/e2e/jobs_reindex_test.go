//go:build e2e

package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestIssue12JobsReindexStrictHTTPHistoryAndOriginalRetention(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	environment = append(environment, "TEMPORAL_UI_URL=", "TEMPORAL_UI_PORT=", "OLLAMA_MAX_QUEUE=9")
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	base, stop := startServer(t, binary, databaseURL, environment)
	defer stop()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	register := func(email string) map[string]any {
		return api.request("", "POST", "/api/v1/auth/register", fmt.Sprintf(`{"accountName":"Jobs acceptance","email":%q,"password":"Jobs acceptance password 2026!"}`, email), 201, "AuthSession")
	}
	owner := register("jobs-owner@example.test")
	token := owner["token"].(string)
	identity := owner["identity"].(map[string]any)
	account := identity["account"].(map[string]any)["id"].(string)
	user := identity["user"].(map[string]any)["id"].(string)
	foreign := register("jobs-foreign@example.test")["token"].(string)
	pipeline := api.request(token, "GET", "/api/v1/document-processing", "", 200, "DocumentProcessingPipeline")
	configuration := pipeline["configuration"].(map[string]any)
	revision := configuration["revision"].(float64)
	system := api.request(token, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	for _, response := range []map[string]any{pipeline, system} {
		if _, present := response["scheduling"]; present {
			t.Fatal("obsolete per-pipeline limits remain", response)
		}
	}
	verifyWorkloadSettings(api, token, foreign)
	if _, present := configuration["scheduling"]; present {
		t.Fatal("runtime scheduling was mixed into immutable processing provenance")
	}
	if system["dashboardUrl"] != "http://localhost:8233" {
		t.Fatalf("default Temporal dashboard URL is missing: %v", system["dashboardUrl"])
	}
	if value, present := system["automaticBatchId"]; !present || value != nil {
		t.Fatalf("initial explicit nullable automaticBatchId is not null: %v", system)
	}
	original := fixtures.PNG(t, "Reindex original remains unchanged")
	document := api.upload(token, "original.png", original, `{"title":"Visible processing title","tags":["retained"]}`, true, 202)
	id := document["id"].(string)
	api.waitProcessing(token, id, "ready")
	t.Run("overlapping job filters avoid authority locks", func(t *testing.T) {
		verifyJobsReadsWhileAuthorityLocked(t, api, databaseURL, token, account, user, id, revision)
	})
	ocr := api.request(token, "GET", "/api/v1/documents/"+id+"/ocr", "", 200, "DocumentOCR")
	correction := map[string]any{"revision": ocr["revision"], "text": "Exact human override\r\n"}
	body, _ := json.Marshal(correction)
	corrected := api.request(token, "PUT", "/api/v1/documents/"+id+"/ocr", string(body), 200, "DocumentOCR")
	api.waitProcessing(token, id, "ready")
	requestID := uuid.NewString()
	request := fmt.Sprintf(`{"requestId":%q,"configurationRevision":%.0f}`, requestID, revision)
	batch := api.request(token, "POST", "/api/v1/document-reindex-batches", request, 202, "DocumentReindexBatch")
	if batch["id"] != requestID {
		t.Fatal("accepted batch lost client request identity")
	}
	same := api.request(token, "POST", "/api/v1/document-reindex-batches", request, 202, "DocumentReindexBatch")
	if same["id"] != requestID {
		t.Fatal("lost-response retry created duplicate batch")
	}
	api.request(foreign, "POST", "/api/v1/document-reindex-batches", request, 404, "Error")
	api.request(token, "POST", "/api/v1/system/document-reindex-batches", request, 404, "Error")
	deadline := time.Now().Add(2 * time.Minute)
	for {
		batch = api.request(token, "GET", "/api/v1/document-reindex-batches/"+requestID, "", 200, "DocumentReindexBatch")
		if batch["status"] == "succeeded" {
			break
		}
		if batch["status"] == "completed_with_failures" || time.Now().After(deadline) {
			t.Fatalf("full reindex did not succeed: %v", batch)
		}
		time.Sleep(200 * time.Millisecond)
	}
	if batch["discovered"] != float64(1) || batch["succeeded"] != float64(1) || batch["skipped"] != float64(0) {
		t.Fatalf("manual original was not fully processed: %v", batch)
	}
	after := api.request(token, "GET", "/api/v1/documents/"+id+"/ocr", "", 200, "DocumentOCR")
	if after["text"] != corrected["text"] || after["revision"] != corrected["revision"] || after["origin"] != "manual" {
		t.Fatalf("reindex replaced human OCR: %v", after)
	}
	api.download(token, id, original, "image/png")
	jobs := api.request(token, "GET", "/api/v1/document-jobs?pipeline=ingestion&limit=1&documentId="+id, "", 200, "DocumentJobPage")
	counts := jobs["counts"].(map[string]any)["groups"].([]any)
	var ingestionTotal float64
	for _, item := range counts {
		group := item.(map[string]any)
		if group["pipeline"] == "ingestion" {
			ingestionTotal += group["count"].(float64)
		}
	}
	if ingestionTotal < 2 {
		t.Fatalf("job totals are page limited or missing: %v", counts)
	}
	active := api.request(token, "GET", "/api/v1/document-jobs?activeOnly=true&pipeline=ingestion&documentId="+id, "", 200, "DocumentJobPage")
	if len(active["items"].([]any)) != 0 || len(active["counts"].(map[string]any)["groups"].([]any)) == 0 {
		t.Fatalf("active filter lost totals or retained terminal jobs: %v", active)
	}
	activeBatches := api.request(token, "GET", "/api/v1/document-reindex-batches?activeOnly=true", "", 200, "DocumentReindexBatchPage")
	for _, row := range activeBatches["items"].([]any) {
		if row.(map[string]any)["id"] == requestID {
			t.Fatal("completed reindex remains active")
		}
	}
	if activeBatches["counts"] == nil {
		t.Fatal("batch totals missing")
	}
	latest := jobs["items"].([]any)[0].(map[string]any)
	if latest["reason"] != "reindex" || latest["status"] != "succeeded" || latest["documentTitle"] != "Visible processing title" || latest["textSource"] != "manual" {
		t.Fatalf("full ingestion history contract: %v", latest)
	}
	cursor := jobs["nextCursor"].(string)
	pagePath := "/api/v1/document-jobs?pipeline=ingestion&limit=1&documentId=" + id + "&cursor=" + url.QueryEscape(cursor)
	api.request(token, "GET", pagePath, "", 200, "DocumentJobPage")
	api.request(token, "GET", "/api/v1/document-jobs?pipeline=ai&limit=1&documentId="+id+"&cursor="+url.QueryEscape(cursor), "", 400, "Error")
	api.request(foreign, "GET", pagePath, "", 400, "Error")
	api.request(token, "GET", "/api/v1/document-reindex-batches?limit=1&cursor="+url.QueryEscape(cursor), "", 400, "Error")
	api.request(foreign, "GET", "/api/v1/document-jobs/"+latest["id"].(string), "", 404, "Error")
	for _, path := range []string{"/api/v1/document-jobs?cursor=", "/api/v1/document-reindex-batches?limit=0", "/api/v1/document-jobs?status=unknown", "/api/v1/document-jobs?pipeline=unknown"} {
		api.request(token, "GET", path, "", 400, "Error")
	}
	for _, invalid := range []string{`{"requestId":null,"configurationRevision":1}`, fmt.Sprintf(`{"requestId":%q,"configurationRevision":1,"configurationRevision":1}`, uuid.NewString()), fmt.Sprintf(`{"requestId":%q,"configurationRevision":1,"extra":true}`, uuid.NewString()), fmt.Sprintf(`{"requestId":%q,"configurationRevision":0}`, uuid.NewString())} {
		api.request(token, "POST", "/api/v1/document-reindex-batches", invalid, 400, "Error")
	}
	api.request(token, "DELETE", "/api/v1/documents/"+id, "", 204, "")
	deleted := api.request(token, "GET", "/api/v1/document-jobs/"+latest["id"].(string), "", 200, "DocumentJob")
	if deleted["status"] != "succeeded" || deleted["documentTitle"] != nil || deleted["documentDeleted"] != true {
		t.Fatalf("deletion rewrote outcome/leaked title: %v", deleted)
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	if _, err = connection.Exec(t.Context(), `UPDATE memberships SET is_owner=false,role='viewer',claims='{}' WHERE account_id=$1 AND user_id=$2`, account, user); err != nil {
		t.Fatal(err)
	}
	api.request(token, "GET", "/api/v1/document-jobs", "", 403, "Error")
	api.request(token, "GET", "/api/v1/document-processing", "", 403, "Error")
	api.request(token, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
}

func verifyJobsReadsWhileAuthorityLocked(t *testing.T, api *ingestionAPI, databaseURL, token, account, user, document string, revision float64) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	blocker, err := connection.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	for _, statement := range []struct {
		query string
		args  []any
	}{
		{"SELECT id FROM accounts WHERE id=$1 FOR UPDATE", []any{account}},
		{"SELECT id FROM users WHERE id=$1 FOR UPDATE", []any{user}},
		{"SELECT user_id FROM memberships WHERE account_id=$1 AND user_id=$2 FOR UPDATE", []any{account, user}},
		{"SELECT digest FROM sessions WHERE account_id=$1 AND user_id=$2 FOR UPDATE", []any{account, user}},
	} {
		if _, err := blocker.Exec(ctx, statement.query, statement.args...); err != nil {
			t.Fatal(err)
		}
	}
	bounded := *api
	bounded.t = t
	bounded.client = &http.Client{Timeout: 3 * time.Second}
	type requestCase struct{ path, schema, pipeline, status string }
	cases := []requestCase{
		{"/api/v1/document-jobs?limit=1&pipeline=ingestion&status=succeeded&documentId=" + document, "DocumentJobPage", "ingestion", "succeeded"},
		{"/api/v1/document-jobs?limit=1&pipeline=ingestion&status=failed&documentId=" + document, "DocumentJobPage", "ingestion", "failed"},
		{"/api/v1/document-jobs?limit=1&pipeline=ingestion&status=queued&documentId=" + document, "DocumentJobPage", "ingestion", "queued"},
		{"/api/v1/document-jobs?limit=1&pipeline=ai&documentId=" + document, "DocumentJobPage", "ai", ""},
		{"/api/v1/document-processing", "DocumentProcessingPipeline", "", ""},
		{"/api/v1/system/document-processing", "DocumentProcessingConfiguration", "", ""},
		{"/api/v1/document-reindex-batches?limit=1", "DocumentReindexBatchPage", "", ""},
		{"/api/v1/system/document-reindex-batches?limit=1", "DocumentReindexBatchPage", "", ""},
	}
	type response struct {
		request requestCase
		status  int
		headers http.Header
		body    []byte
		err     error
	}
	start := make(chan struct{})
	results := make(chan response, len(cases)*2)
	for range 2 {
		for _, request := range cases {
			go func() {
				<-start
				status, headers, body, err := bounded.send(token, http.MethodGet, request.path, "application/json", nil)
				results <- response{request: request, status: status, headers: headers, body: body, err: err}
			}()
		}
	}
	close(start)
	for range len(cases) * 2 {
		response := <-results
		value := bounded.decode(response.status, response.headers, response.body, response.err, http.StatusOK, response.request.schema)
		switch response.request.schema {
		case "DocumentJobPage":
			items := value["items"].([]any)
			if len(items) > 1 || response.request.status == "succeeded" && len(items) != 1 {
				t.Fatalf("wrong filtered page for %s: %v", response.request.path, value)
			}
			for _, item := range items {
				job := item.(map[string]any)
				if job["documentId"] != document || job["pipeline"] != response.request.pipeline || response.request.status != "" && job["status"] != response.request.status {
					t.Fatalf("filter changed during overlapping requests %s: %v", response.request.path, job)
				}
				if job["documentTitle"] != "Visible processing title" {
					t.Fatalf("authorized title missing from filtered response: %v", job)
				}
			}
		case "DocumentProcessingPipeline":
			if value["configuration"].(map[string]any)["revision"] != revision {
				t.Fatalf("namespace configuration changed during reads: %v", value)
			}
		case "DocumentProcessingConfiguration":
			if value["revision"] != revision {
				t.Fatalf("system configuration changed during reads: %v", value)
			}
		case "DocumentReindexBatchPage":
			if len(value["items"].([]any)) != 0 {
				t.Fatalf("unexpected batch before explicit reindex: %v", value)
			}
		}
	}
}
