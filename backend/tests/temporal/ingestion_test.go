//go:build temporal

package temporal_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/bootstrap"
	"github.com/domabas/domabas/backend/internal/config"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"

	temporaldata "github.com/domabas/domabas/backend/internal/data/temporal"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"

	documenttemporal "github.com/domabas/domabas/backend/internal/data/document/temporal"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	enumspb "go.temporal.io/api/enums/v1"

	historypb "go.temporal.io/api/history/v1"

	temporallog "go.temporal.io/sdk/log"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

type extractionGate struct {
	proxy     http.Handler
	mu        sync.Mutex
	entered   chan struct{}
	release   chan struct{}
	remaining int
	path      string
	canceled  chan struct{}
}

func (gate *extractionGate) arm() (<-chan struct{}, func()) {
	return gate.armCount(1)
}

func (gate *extractionGate) armCount(count int) (<-chan struct{}, func()) {
	return gate.armPathCount("/internal/v1/extract", count)
}

func (gate *extractionGate) armPathCount(path string, count int) (<-chan struct{}, func()) {
	gate.mu.Lock()
	defer gate.mu.Unlock()
	gate.entered, gate.release, gate.remaining = make(chan struct{}), make(chan struct{}), count
	gate.path, gate.canceled = path, make(chan struct{}, count)
	var once sync.Once
	release := gate.release
	return gate.entered, func() { once.Do(func() { close(release) }) }
}

func (gate *extractionGate) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	gate.mu.Lock()
	var release chan struct{}
	var entered chan struct{}
	var canceled chan struct{}
	if request.URL.Path == gate.path && gate.remaining > 0 {
		gate.remaining--
		release = gate.release
		canceled = gate.canceled
		if gate.remaining == 0 {
			entered = gate.entered
		}
	}
	gate.mu.Unlock()
	if release != nil {
		data, err := io.ReadAll(io.LimitReader(request.Body, 21<<20))
		request.Body.Close()
		if err != nil {
			http.Error(writer, "test transfer interrupted", http.StatusBadRequest)
			return
		}
		request.Body = io.NopCloser(bytes.NewReader(data))
		request.ContentLength = int64(len(data))
		request.TransferEncoding = nil
		if entered != nil {
			close(entered)
		}
		select {
		case <-request.Context().Done():
			canceled <- struct{}{}
			return
		case <-release:
		}
	}
	gate.proxy.ServeHTTP(writer, request)
}

func TestRealIngestionResumesAndReconcilesTerminalWork(t *testing.T) {
	address, namespace, processor := os.Getenv("TEMPORAL_ADDRESS"), os.Getenv("TEMPORAL_NAMESPACE"), os.Getenv("DOCUMENT_PROCESSOR_URL")
	if address == "" || namespace == "" || processor == "" {
		t.Fatal("TEMPORAL_ADDRESS, TEMPORAL_NAMESPACE and DOCUMENT_PROCESSOR_URL are required for real ingestion tests")
	}
	processorURL, err := url.Parse(processor)
	if err != nil {
		t.Fatal(err)
	}
	gate := &extractionGate{proxy: httputil.NewSingleHostReverseProxy(processorURL)}
	processorProxy := httptest.NewServer(gate)
	defer processorProxy.Close()
	ollamaOrigin := os.Getenv("LLM_OLLAMA_URL")
	if ollamaOrigin == "" {
		ollamaOrigin = "http://127.0.0.1:11435"
	}
	storage := t.TempDir()
	settings := config.BackendConfig{
		OllamaMaxQueue: 128, LLMOllamaURL: ollamaOrigin,
		DatabaseURL: testdb.New(t), HTTPAddress: "127.0.0.1:0",
		TemporalAddress: address, TemporalNamespace: namespace, TemporalTaskQueue: "domabas-ingestion-test-" + uuid.NewString(),
		DocumentProcessorURL: processorProxy.URL, DocumentIngestionRoot: filepath.Join(storage, "ingestion"), DocumentStorageRoot: filepath.Join(storage, "documents"),
	}
	ctx, cancel := context.WithTimeout(t.Context(), 6*time.Minute)
	defer cancel()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	source, err := temporaldata.NewTemporalDataSource(ctx, address, namespace, logger)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	connection, err := pgx.Connect(ctx, settings.DatabaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	var app *bootstrap.BackendApp
	var server *httptest.Server
	var owned []string
	defer func() {
		if server != nil {
			server.Close()
		}
		if app != nil {
			app.Close()
		}
		cleanupOwnedThumbnailExecutions(t, connection, source.Client(), settings.TemporalTaskQueue+"-thumbnail")
		cleanup, stop := context.WithTimeout(context.Background(), 10*time.Second)
		defer stop()
		for _, workflowID := range owned {
			info, err := source.Client().DescribeWorkflowExecution(cleanup, workflowID, "")
			if err == nil && info.GetWorkflowExecutionInfo().GetStatus() == enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING {
				if err := source.Client().TerminateWorkflow(cleanup, workflowID, info.GetWorkflowExecutionInfo().GetExecution().GetRunId(), "owned ingestion test cleanup"); err != nil {
					t.Errorf("terminate owned workflow: %v", err)
				}
			}
		}
	}()
	start := func() {
		t.Helper()
		startup, stop := context.WithTimeout(ctx, 30*time.Second)
		app, err = bootstrap.NewBackendApp(startup, settings, logger)
		stop()
		if err != nil {
			t.Fatal(err)
		}
		if _, err := connection.Exec(ctx, "UPDATE document_thumbnail_scan SET next_scan_at=clock_timestamp()+interval '1 day' WHERE singleton"); err != nil {
			t.Fatal(err)
		}
		server = httptest.NewServer(app.Handler)
		if err := app.Ping(ctx); err != nil {
			t.Fatal(err)
		}
	}
	start()
	client := &http.Client{Timeout: 15 * time.Second}
	request := func(token, method, path, contentType string, body io.Reader, expected int) map[string]any {
		t.Helper()
		request, err := http.NewRequestWithContext(ctx, method, server.URL+path, body)
		if err != nil {
			t.Fatal(err)
		}
		request.Header.Set("Content-Type", contentType)
		request.Header.Set("Authorization", "Bearer "+token)
		if token == "" {
			request.Header.Del("Authorization")
		}
		response, err := client.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
		if err != nil || response.StatusCode != expected {
			t.Fatalf("%s %s: status %d, want %d: %v %s", method, path, response.StatusCode, expected, err, data)
		}
		var result map[string]any
		if expected == http.StatusNoContent {
			if len(data) != 0 {
				t.Fatal("no-content response included a body")
			}
			return nil
		}
		if err := json.Unmarshal(data, &result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	registration := request("", "POST", "/api/v1/auth/register", "application/json", strings.NewReader(`{"accountName":"Temporal ingestion","email":"ingestion@example.test","password":"Temporal ingestion password 2026!"}`), 201)
	token := registration["token"].(string)
	accountID := registration["identity"].(map[string]any)["account"].(map[string]any)["id"].(string)
	workloads := request(token, "GET", "/api/v1/system/workload-settings", "", nil, 200)
	request(token, "PUT", "/api/v1/system/workload-settings", "application/json", strings.NewReader(fmt.Sprintf(`{"expectedRevision":%.0f,"resources":[{"id":"worker","limit":10},{"id":"ollama","limit":10}]}`, workloads["revision"])), 200)
	upload := func(text string) string {
		t.Helper()
		var body bytes.Buffer
		writer := multipart.NewWriter(&body)
		if err := writer.WriteField("metadata", `{"title":"Old uniquetitle","subject":"Original manual subject"}`); err != nil {
			t.Fatal(err)
		}
		part, err := writer.CreateFormFile("file", "private-original.png")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := part.Write(fixtures.PNG(t, text)); err != nil {
			t.Fatal(err)
		}
		if err := writer.Close(); err != nil {
			t.Fatal(err)
		}
		doc := request(token, "POST", "/api/v1/documents/upload", writer.FormDataContentType(), &body, 202)
		id := doc["id"].(string)
		owned = append(owned, documenttemporal.IngestionWorkflowID(document.DocumentJob{AccountID: accountID, DocumentID: id, Generation: 1}, true))
		return id
	}
	waitEntered := func(entered <-chan struct{}) {
		t.Helper()
		select {
		case <-entered:
		case <-time.After(30 * time.Second):
			gate.mu.Lock()
			remaining := gate.remaining
			gate.mu.Unlock()
			t.Logf("processor requests still missing: %d", remaining)
			rows, err := connection.Query(ctx, `SELECT 'processing',state,stage,count(*) FROM document_processing GROUP BY state,stage UNION ALL SELECT 'scheduler',pipeline,state,count(*) FROM scheduler_requests GROUP BY pipeline,state`)
			if err == nil {
				for rows.Next() {
					var kind, state, stage string
					var count int
					if err := rows.Scan(&kind, &state, &stage, &count); err == nil {
						t.Logf("%s %s %s: %d", kind, state, stage, count)
					}
				}
				rows.Close()
			}
			t.Fatal("durable ingestion did not reach the real processor boundary")
		}
	}
	waitState := func(id, state string) map[string]any {
		t.Helper()
		deadline := time.Now().Add(90 * time.Second)
		for time.Now().Before(deadline) {
			result := request(token, "GET", "/api/v1/documents/"+id+"/processing", "", nil, 200)
			if result["state"] == state {
				return result
			}
			if result["state"] == "ready" || result["state"] == "failed" {
				t.Fatalf("unexpected terminal processing state: %v", result)
			}
			time.Sleep(100 * time.Millisecond)
		}
		t.Fatal("processing did not reach expected durable state")
		return nil
	}

	entered, release := gate.arm()
	defer release()
	id := upload("Private astrophysics report about distant galaxies")
	waitEntered(entered)
	request(token, "PATCH", "/api/v1/documents/"+id, "application/json", strings.NewReader(`{"title":"New preservedtitle","subject":"Edited during ingestion"}`), 200)
	server.Close()
	server = nil
	app.Close()
	app = nil
	release()
	start()
	waitState(id, "ready")
	retained := request(token, "GET", "/api/v1/documents/"+id, "", nil, 200)
	if retained["title"] != "New preservedtitle" || retained["subject"] != "Edited during ingestion" {
		t.Fatal("resumed ingestion overwrote current manual metadata")
	}
	for _, check := range []struct {
		query string
		total float64
	}{{"preservedtitle", 1}, {"uniquetitle", 0}, {"galaxies", 1}} {
		body, _ := json.Marshal(map[string]string{"query": check.query, "mode": "fulltext"})
		found := request(token, "POST", "/api/v1/documents/search", "application/json", bytes.NewReader(body), 200)
		if found["total"] != check.total {
			t.Fatalf("resumed metadata/content search %s: %v", check.query, found)
		}
	}
	firstWorkflowID := owned[0]
	if err := source.Client().GetWorkflow(ctx, firstWorkflowID, "").Get(ctx, nil); err != nil {
		t.Fatalf("worker restart did not preserve successful ingestion: %v", err)
	}
	history := source.Client().GetWorkflowHistory(ctx, firstWorkflowID, "", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	replayHistory := &historypb.History{}
	for history.HasNext() {
		event, err := history.Next()
		if err != nil {
			t.Fatal(err)
		}
		data := event.String()
		replayHistory.Events = append(replayHistory.Events, event)
		if started := event.GetWorkflowExecutionStartedEventAttributes(); started != nil {
			payloads := started.GetInput().GetPayloads()
			if len(payloads) != 1 {
				t.Fatal("ingestion input payload shape changed")
			}
			var fields map[string]any
			if err := json.Unmarshal(payloads[0].GetData(), &fields); err != nil || len(fields) != 4 || fields["unlimitedInference"] != true || fields["accountId"] != accountID || fields["documentId"] != id || fields["generation"] != float64(1) {
				t.Fatalf("ingestion identity or execution mode changed: %v %v", fields, err)
			}
		}
		for _, secret := range []string{"Private astrophysics", "uniquetitle", "preservedtitle", "private-original.png", storage, processor} {
			if strings.Contains(data, secret) {
				t.Fatalf("private ingestion value entered workflow history: %q", secret)
			}
		}
	}
	replayer := worker.NewWorkflowReplayer()
	replayer.RegisterWorkflowWithOptions(documentworkflows.DocumentSearchableWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentSearchableWorkflowName})
	if err := replayer.ReplayWorkflowHistory(temporallog.NewStructuredLogger(logger), replayHistory); err != nil {
		t.Fatalf("unlimited ingestion history did not replay: %v", err)
	}

	entered, releaseSlowEmbedding := gate.armPathCount("/internal/v1/embed", 1)
	defer releaseSlowEmbedding()
	slowID := upload("Embedding must survive a long local model queue")
	waitEntered(entered)
	gate.mu.Lock()
	canceledEmbedding := gate.canceled
	gate.mu.Unlock()
	select {
	case <-canceledEmbedding:
		t.Fatal("embedding was canceled while waiting beyond the former request deadline")
	case <-time.After(125 * time.Second):
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	releaseSlowEmbedding()
	waitState(slowID, "ready")

	for _, scenario := range []struct {
		name, correction, indexing string
		deletion                   bool
	}{
		{name: "Correction", correction: "manualrevisionneedle\r\n", indexing: "ready"},
		{name: "Empty correction", correction: "", indexing: "not_required"},
		{name: "Deletion", deletion: true},
	} {
		entered, release := gate.arm()
		defer release()
		id := upload(scenario.name + " race machine original")
		waitEntered(entered)
		path := "/api/v1/documents/" + id
		oldWorkflowID := documenttemporal.IngestionWorkflowID(document.DocumentJob{AccountID: accountID, DocumentID: id, Generation: 1}, true)
		if scenario.deletion {
			request(token, "DELETE", path, "", nil, 204)
		} else {
			body, err := json.Marshal(map[string]any{"revision": 0, "text": scenario.correction})
			if err != nil {
				t.Fatal(err)
			}
			corrected := request(token, "PUT", path+"/ocr", "application/json", bytes.NewReader(body), 200)
			if corrected["revision"] != float64(1) || corrected["text"] != scenario.correction {
				t.Fatalf("correction while extraction paused: %v", corrected)
			}
			owned = append(owned, documenttemporal.IngestionWorkflowID(document.DocumentJob{AccountID: accountID, DocumentID: id, Generation: 2}, true))
		}
		release()
		if err := source.Client().GetWorkflow(ctx, oldWorkflowID, "").Get(ctx, nil); err == nil {
			t.Fatal("paused old generation completed after correction or deletion")
		}
		if scenario.deletion {
			request(token, "GET", path+"/ocr", "", nil, 404)
			request(token, "GET", path+"/content", "", nil, 404)
			var retained int
			if err := connection.QueryRow(ctx, `SELECT (SELECT count(*) FROM documents WHERE id=$1)+(SELECT count(*) FROM document_chunks WHERE document_id=$1)+(SELECT count(*) FROM document_processing WHERE document_id=$1)`, id).Scan(&retained); err != nil || retained != 0 {
				t.Fatalf("late extraction revived deleted content: %d %v", retained, err)
			}
		} else {
			waitState(id, "ready")
			current := request(token, "GET", path+"/ocr", "", nil, 200)
			if current["text"] != scenario.correction || current["revision"] != float64(1) || current["origin"] != "manual" || current["semanticIndexing"] != scenario.indexing {
				t.Fatalf("late extraction or failure compensation overwrote current correction: %v", current)
			}
			var stale int
			if err := connection.QueryRow(ctx, "SELECT count(*) FROM document_chunks WHERE document_id=$1 AND generation<>2", id).Scan(&stale); err != nil || stale != 0 {
				t.Fatalf("late extraction left stale chunks: %d %v", stale, err)
			}
			var location string
			if err := connection.QueryRow(ctx, "SELECT location FROM document_files WHERE document_id=$1", id).Scan(&location); err != nil || location != "final" {
				t.Fatalf("correction did not publish original: %q %v", location, err)
			}
		}
	}

	entered, releaseQueued := gate.armCount(10)
	defer releaseQueued()
	queuedIDs := []string{}
	for i := range 12 {
		queuedIDs = append(queuedIDs, upload(fmt.Sprintf("Concurrent document %d preserves durable processor capacity", i)))
	}
	waitEntered(entered)
	ackDeadline := time.Now().Add(15 * time.Second)
	for {
		var acknowledged, admitted, waiting int
		if err := connection.QueryRow(ctx, `SELECT
 (SELECT count(*) FROM document_processing WHERE document_id=ANY($1::uuid[]) AND run_id<>''),
 (SELECT count(*) FROM document_processing_executions WHERE document_id=ANY($1::uuid[]) AND closed_at IS NULL),
 (SELECT count(*) FROM document_outbox o JOIN document_processing p ON p.document_id=o.document_id AND p.generation=o.generation WHERE o.document_id=ANY($1::uuid[]) AND o.delivery_deadline IS NULL AND p.delivery_deadline IS NULL AND p.processing_deadline IS NULL AND p.run_id='' AND o.acknowledged_at IS NULL)`, queuedIDs).Scan(&acknowledged, &admitted, &waiting); err != nil {
			t.Fatal(err)
		}
		if acknowledged > 10 || admitted > 10 {
			t.Fatalf("concurrent uploads exceeded shared admission: acknowledged=%d admitted=%d", acknowledged, admitted)
		}
		if acknowledged == 10 && admitted == 10 && waiting == 2 {
			break
		}
		if time.Now().After(ackDeadline) {
			t.Fatalf("accepted uploads lost durable admission or waiting outboxes: acknowledged=%d admitted=%d waiting=%d", acknowledged, admitted, waiting)
		}
		time.Sleep(50 * time.Millisecond)
	}
	for _, queuedID := range queuedIDs[10:] {
		queued := request(token, "GET", "/api/v1/documents/"+queuedID+"/processing", "", nil, 200)
		if queued["state"] != "queued" {
			t.Fatalf("CPU worker did not leave excess accepted work in the durable queue: %v", queued)
		}
	}
	releaseQueued()
	for _, queuedID := range queuedIDs {
		waitState(queuedID, "ready")
	}

	for _, terminal := range []string{"terminated", "deadline"} {
		entered, release := gate.arm()
		defer release()
		id := upload("Recoverable " + terminal + " document with original bytes")
		waitEntered(entered)
		workflowID := documenttemporal.IngestionWorkflowID(document.DocumentJob{AccountID: accountID, DocumentID: id, Generation: 1}, true)
		if terminal == "terminated" {
			if err := source.Client().TerminateWorkflow(ctx, workflowID, "", "owned termination reconciliation test"); err != nil {
				t.Fatal(err)
			}
		} else {
			if _, err := connection.Exec(ctx, `UPDATE document_processing SET processing_deadline=clock_timestamp()-interval '1 second' WHERE account_id=$1 AND document_id=$2 AND generation=1`, accountID, id); err != nil {
				t.Fatal(err)
			}
		}
		failed := waitState(id, "failed")
		expectedCode := "processing_terminated"
		if terminal == "deadline" {
			expectedCode = "processing_timeout"
		}
		if failed["failureCode"] != expectedCode {
			t.Fatalf("terminal reconciliation failed: %v", failed)
		}
		release()
		if terminal == "deadline" {
			if err := source.Client().GetWorkflow(ctx, workflowID, "").Get(ctx, nil); err == nil {
				t.Fatal("late activity succeeded after the database fenced its generation")
			}
		}
		retried := request(token, "POST", "/api/v1/documents/"+id+"/retry", "", nil, 202)
		if retried["generation"] != float64(2) {
			t.Fatal("retry did not create a new generation")
		}
		owned = append(owned, documenttemporal.IngestionWorkflowID(document.DocumentJob{AccountID: accountID, DocumentID: id, Generation: 2}, true))
		waitState(id, "ready")
		var stale int
		if err := connection.QueryRow(ctx, `SELECT count(*) FROM document_chunks WHERE document_id=$1 AND generation=1 AND embedding IS NOT NULL`, id).Scan(&stale); err != nil && !errors.Is(err, pgx.ErrNoRows) {
			t.Fatal(err)
		}
		if stale != 0 {
			t.Fatal("fenced generation published stale embeddings")
		}
	}
}
