//go:build jobs

package jobs_test

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/domabas/domabas/backend/internal/bootstrap"
	"github.com/domabas/domabas/backend/internal/config"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	"github.com/jackc/pgx/v5"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestUploadResumesEmbeddingAfterWorkerRestart(t *testing.T) {
	var thumbnails, recognitions, embeddings atomic.Int32
	entered := make(chan struct{})
	unblock := make(chan struct{})
	processor := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/readyz":
			w.WriteHeader(200)
		case "/internal/v1/thumbnail":
			thumbnails.Add(1)
			http.Error(w, `{"code":"unsupported_media"}`, 422)
		case "/internal/v1/extract":
			recognitions.Add(1)
			c := document.DefaultConfiguration()
			json.NewEncoder(w).Encode(map[string]any{"pages": 1, "extractionRevision": c.ExtractionRevision, "engine": c.Engine, "engineVersion": c.EngineVersion, "weights": c.Weights, "text": "Native worker search fixture"})
		case "/internal/v1/embed":
			var input struct {
				Space  document.DocumentEmbeddingSpace
				Inputs []string
			}
			if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
				http.Error(w, err.Error(), 400)
				return
			}
			if embeddings.Add(1) == 1 {
				close(entered)
				select {
				case <-r.Context().Done():
					return
				case <-unblock:
				}
			}
			vectors := make([][]float64, len(input.Inputs))
			for i := range vectors {
				vectors[i] = make([]float64, input.Space.Dimensions)
				vectors[i][0] = 1
			}
			json.NewEncoder(w).Encode(map[string]any{"space": input.Space, "model": input.Space.Model, "digest": input.Space.Digest, "vectors": vectors})
		default:
			http.NotFound(w, r)
		}
	}))
	defer processor.Close()
	defer close(unblock)
	storage := t.TempDir()
	settings := config.BackendConfig{EmbeddingQueueSize: 128, DatabaseURL: testdb.New(t), DocumentProcessorURL: processor.URL, DocumentIngestionRoot: filepath.Join(storage, "ingestion"), DocumentStorageRoot: filepath.Join(storage, "documents")}
	ctx, cancel := context.WithTimeout(t.Context(), 50*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, settings.DatabaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	var app *bootstrap.BackendApp
	var server *httptest.Server
	start := func() {
		t.Helper()
		app, err = bootstrap.NewBackendApp(ctx, settings, slog.Default())
		if err != nil {
			t.Fatal(err)
		}
		server = httptest.NewServer(app.Handler)
	}
	stop := func() {
		if server != nil {
			server.Close()
			server = nil
		}
		if app != nil {
			app.Close()
			app = nil
		}
	}
	defer stop()
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
	registration := request("", "POST", "/api/v1/auth/register", "application/json", strings.NewReader(`{"accountName":"Native ingestion","email":"ingestion@example.test","password":"Native ingestion password 2026!"}`), 201)
	token := registration["token"].(string)
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
		return id
	}
	socket, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/realtime?workload=true", &websocket.DialOptions{Subprotocols: []string{"domabas.realtime.v1"}})
	if err != nil {
		t.Fatal(err)
	}
	defer socket.CloseNow()
	if err := wsjson.Write(ctx, socket, map[string]any{"version": 1, "type": "authenticate", "token": token}); err != nil {
		t.Fatal(err)
	}
	awaitWorkloadHint := func(kind string) {
		t.Helper()
		deadline, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		for {
			var frame struct {
				Type   string
				Topics []string
			}
			if err := wsjson.Read(deadline, socket, &frame); err != nil {
				t.Fatalf("await %s workload hint: %v", kind, err)
			}
			if frame.Type == kind && slices.Contains(frame.Topics, "workload") {
				return
			}
		}
	}
	awaitWorkloadHint("ready")
	id := upload("worker restart")
	select {
	case <-entered:
	case <-ctx.Done():
		var state, stage, code string
		connection.QueryRow(t.Context(), "SELECT state,stage,COALESCE(failure_code,'') FROM document_processing WHERE document_id=$1", id).Scan(&state, &stage, &code)
		t.Fatalf("embedding never entered: state=%s stage=%s error=%s", state, stage, code)
	}
	awaitWorkloadHint("invalidate")
	socket.CloseNow()
	workload := request(token, "GET", "/api/v1/system/workload-settings", "", nil, http.StatusOK)
	var ingestionSlots map[string]any
	for _, entry := range workload["pipelines"].([]any) {
		pipeline := entry.(map[string]any)
		if pipeline["id"] == "document_ingestion" {
			ingestionSlots = pipeline["activeSlots"].(map[string]any)
		}
	}
	if ingestionSlots["stage:embedding"] != float64(1) || ingestionSlots["embedding-runtime"] != float64(1) || ingestionSlots["stage:ocr"] != float64(0) {
		t.Fatalf("HTTP workload snapshot does not reflect running job: %v", ingestionSlots)
	}
	var holds int
	if err := connection.QueryRow(ctx, "SELECT count(*) FROM scheduler_step_permits WHERE resource_id IN ('embedding-runtime','stage:embedding')").Scan(&holds); err != nil || holds != 2 {
		t.Fatal("missing embedding permits", holds, err)
	}
	stop()
	start()
	for ctx.Err() == nil {
		var ready bool
		if err = connection.QueryRow(ctx, "SELECT state='ready' FROM document_processing WHERE document_id=$1", id).Scan(&ready); err != nil {
			t.Fatal(err)
		}
		if ready {
			if thumbnails.Load() != 1 || recognitions.Load() != 1 || embeddings.Load() != 2 {
				t.Fatal("unexpected stage replay", thumbnails.Load(), recognitions.Load(), embeddings.Load())
			}
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("restarted worker did not finish")
}
