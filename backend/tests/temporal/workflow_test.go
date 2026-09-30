//go:build temporal

package temporal_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/bootstrap"
	"github.com/domabas/domabas/backend/internal/config"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"

	temporaldata "github.com/domabas/domabas/backend/internal/data/temporal"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"

	temporalsdk "go.temporal.io/sdk/temporal"
)

func TestDocumentWorkflowPersistsWhileWorkerIsStopped(t *testing.T) {
	address, namespace := os.Getenv("TEMPORAL_ADDRESS"), os.Getenv("TEMPORAL_NAMESPACE")
	if address == "" || namespace == "" {
		t.Fatal("TEMPORAL_ADDRESS and TEMPORAL_NAMESPACE are required for real Temporal tests")
	}
	processor := os.Getenv("DOCUMENT_PROCESSOR_URL")
	if processor == "" {
		t.Fatal("DOCUMENT_PROCESSOR_URL is required for real Temporal tests")
	}
	ollamaOrigin := os.Getenv("LLM_OLLAMA_URL")
	if ollamaOrigin == "" {
		ollamaOrigin = "http://127.0.0.1:11435"
	}
	storage := t.TempDir()
	settings := config.BackendConfig{
		OllamaMaxQueue: 128, LLMOllamaURL: ollamaOrigin,
		DatabaseURL: testdb.New(t), HTTPAddress: "127.0.0.1:0",
		TemporalAddress: address, TemporalNamespace: namespace,
		TemporalTaskQueue:     "domabas-test-" + uuid.NewString(),
		DocumentProcessorURL:  processor,
		DocumentIngestionRoot: filepath.Join(storage, "ingestion"),
		DocumentStorageRoot:   filepath.Join(storage, "documents"),
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	ctx, cancel := context.WithTimeout(t.Context(), 90*time.Second)
	defer cancel()
	missingNamespace := settings
	missingNamespace.TemporalNamespace = "domabas-missing-" + uuid.NewString()
	startup, startupCancel := context.WithTimeout(ctx, 5*time.Second)
	unexpected, startupErr := bootstrap.NewBackendApp(startup, missingNamespace, logger)
	startupCancel()
	if unexpected != nil {
		unexpected.Close()
		t.Fatal("startup silently accepted an unregistered namespace")
	}
	if startupErr == nil {
		t.Fatal("startup must reject an unregistered namespace")
	}
	source, err := temporaldata.NewTemporalDataSource(ctx, address, namespace, logger)
	if err != nil {
		t.Fatal(err)
	}
	var app *bootstrap.BackendApp
	var server *httptest.Server
	var execution client.WorkflowRun
	completed := false
	t.Cleanup(func() {
		if execution != nil && !completed {
			cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cleanupCancel()
			if err := source.Client().TerminateWorkflow(cleanupCtx, execution.GetID(), execution.GetRunID(), "test cleanup"); err != nil {
				t.Errorf("terminate owned test workflow: %v", err)
			}
		}
		if server != nil {
			server.Close()
		}
		if app != nil {
			app.Close()
		}
		source.Close()
	})
	start := func() {
		t.Helper()
		startup, startupCancel := context.WithTimeout(ctx, 20*time.Second)
		app, err = bootstrap.NewBackendApp(startup, settings, logger)
		startupCancel()
		if err != nil {
			t.Fatal(err)
		}
		if err := app.Ping(ctx); err != nil {
			t.Fatalf("started worker not ready: %v", err)
		}
		server = httptest.NewServer(app.Handler)
	}
	start()
	registration, err := http.Post(server.URL+"/api/v1/auth/register", "application/json", strings.NewReader(`{"accountName":"Temporal test","email":"temporal@example.test","password":"Temporal strong password 2026"}`))
	if err != nil {
		t.Fatal(err)
	}
	var session struct {
		Token    string `json:"token"`
		Identity struct {
			Account struct {
				ID string `json:"id"`
			} `json:"account"`
		} `json:"identity"`
	}
	registrationErr := json.NewDecoder(registration.Body).Decode(&session)
	registration.Body.Close()
	if registration.StatusCode != http.StatusCreated || registrationErr != nil || session.Token == "" {
		t.Fatalf("register: %d %v", registration.StatusCode, registrationErr)
	}
	request, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/documents", strings.NewReader(`{"title":"Private document","description":"Not copied to workflow history"}`))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+session.Token)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	var persisted documentworkflows.DocumentMetadataResult
	decodeErr := json.NewDecoder(response.Body).Decode(&persisted)
	response.Body.Close()
	if response.StatusCode != http.StatusCreated || decodeErr != nil {
		t.Fatalf("create document: status %d, decode %v", response.StatusCode, decodeErr)
	}
	server.Close()
	server = nil
	app.Close()
	if err := app.Ping(ctx); err == nil {
		t.Fatal("stopped worker remained ready")
	}
	app = nil
	execution, err = source.Client().ExecuteWorkflow(ctx, client.StartWorkflowOptions{
		ID: "domabas-restart-test-" + uuid.NewString(), TaskQueue: settings.TemporalTaskQueue,
		WorkflowExecutionTimeout: time.Minute,
	}, documentworkflows.DocumentMetadataWorkflowName, documentworkflows.DocumentMetadataRequest{AccountID: session.Identity.Account.ID, DocumentID: persisted.ID})
	if err != nil {
		t.Fatal(err)
	}
	legacy, err := source.Client().ExecuteWorkflow(ctx, client.StartWorkflowOptions{ID: "domabas-legacy-test-" + uuid.NewString(), TaskQueue: settings.TemporalTaskQueue, WorkflowExecutionTimeout: time.Minute}, documentworkflows.LegacyDocumentMetadataWorkflowName, persisted.ID)
	if err != nil {
		t.Fatal(err)
	}
	legacyComplete := false
	t.Cleanup(func() {
		if !legacyComplete {
			cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = source.Client().TerminateWorkflow(cleanup, legacy.GetID(), legacy.GetRunID(), "test cleanup")
		}
	})
	waitCtx, waitCancel := context.WithTimeout(ctx, 200*time.Millisecond)
	var result documentworkflows.DocumentMetadataResult
	err = execution.Get(waitCtx, &result)
	waitCancel()
	var rpcDeadline *serviceerror.DeadlineExceeded
	if !errors.Is(err, context.DeadlineExceeded) && !errors.As(err, &rpcDeadline) {
		t.Fatalf("workflow should wait for absent worker: %v", err)
	}
	start()
	if err := execution.Get(ctx, &result); err != nil {
		t.Fatal(err)
	}
	completed = true
	var legacyFailure *temporalsdk.ApplicationError
	if err := legacy.Get(ctx, nil); !errors.As(err, &legacyFailure) || !legacyFailure.NonRetryable() || legacyFailure.Type() != "AccountScopeRequired" {
		t.Fatalf("queued legacy work did not fail closed: %v", err)
	}
	legacyComplete = true
	wrongAccount, err := source.Client().ExecuteWorkflow(ctx, client.StartWorkflowOptions{ID: "domabas-wrong-account-test-" + uuid.NewString(), TaskQueue: settings.TemporalTaskQueue, WorkflowExecutionTimeout: time.Minute}, documentworkflows.DocumentMetadataWorkflowName, documentworkflows.DocumentMetadataRequest{AccountID: uuid.NewString(), DocumentID: persisted.ID})
	if err != nil {
		t.Fatal(err)
	}
	wrongComplete := false
	t.Cleanup(func() {
		if !wrongComplete {
			cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = source.Client().TerminateWorkflow(cleanup, wrongAccount.GetID(), wrongAccount.GetRunID(), "test cleanup")
		}
	})
	var scopeFailure *temporalsdk.ApplicationError
	if err := wrongAccount.Get(ctx, nil); !errors.As(err, &scopeFailure) || !scopeFailure.NonRetryable() || scopeFailure.Type() != "DocumentNotFound" {
		t.Fatalf("wrong-account workflow accessible: %v", err)
	}
	wrongComplete = true
	if result.ID != persisted.ID || !result.CreatedAt.Equal(persisted.CreatedAt) {
		t.Fatalf("result %+v differs from persisted metadata %+v", result, persisted)
	}
}
