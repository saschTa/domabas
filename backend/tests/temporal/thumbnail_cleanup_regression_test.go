//go:build temporal

package temporal_test

import (
	"context"
	"io"
	"log/slog"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	temporaldata "github.com/domabas/domabas/backend/internal/data/temporal"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	commonpb "go.temporal.io/api/common/v1"
	enumspb "go.temporal.io/api/enums/v1"
	workflowpb "go.temporal.io/api/workflow/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

func TestThumbnailCleanupRejectsMismatchedExecutionOwnership(t *testing.T) {
	job := uuid.NewString()
	owner := thumbnailCleanupOwner{jobID: job, workflowID: "document-thumbnail-v1/" + job, runID: "owned-run", queue: "owned-thumbnail-queue"}
	for _, scenario := range []struct {
		name   string
		change func(*thumbnailCleanupOwner, *workflowpb.WorkflowExecutionInfo)
	}{
		{name: "job identity", change: func(o *thumbnailCleanupOwner, _ *workflowpb.WorkflowExecutionInfo) { o.jobID = uuid.NewString() }},
		{name: "ledger queue", change: func(o *thumbnailCleanupOwner, _ *workflowpb.WorkflowExecutionInfo) { o.queue = "foreign-queue" }},
		{name: "workflow identity", change: func(_ *thumbnailCleanupOwner, i *workflowpb.WorkflowExecutionInfo) {
			i.Execution.WorkflowId = "foreign-workflow"
		}},
		{name: "run identity", change: func(_ *thumbnailCleanupOwner, i *workflowpb.WorkflowExecutionInfo) { i.Execution.RunId = "foreign-run" }},
		{name: "missing run", change: func(_ *thumbnailCleanupOwner, i *workflowpb.WorkflowExecutionInfo) { i.Execution.RunId = "" }},
		{name: "workflow type", change: func(_ *thumbnailCleanupOwner, i *workflowpb.WorkflowExecutionInfo) { i.Type.Name = "foreign-type" }},
		{name: "execution queue", change: func(_ *thumbnailCleanupOwner, i *workflowpb.WorkflowExecutionInfo) { i.TaskQueue = "foreign-queue" }},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			current := owner
			info := &workflowpb.WorkflowExecutionInfo{Execution: &commonpb.WorkflowExecution{WorkflowId: owner.workflowID, RunId: owner.runID}, Type: &commonpb.WorkflowType{Name: documentworkflows.DocumentThumbnailWorkflowName}, TaskQueue: owner.queue}
			scenario.change(&current, info)
			if _, err := thumbnailCleanupRun(current, &workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: info}, owner.queue); err == nil {
				t.Fatal("accepted foreign cleanup execution")
			}
		})
	}
}

func thumbnailCleanupWait(ctx workflow.Context, _ documentworkflows.DocumentThumbnailRequest) error {
	return workflow.Sleep(ctx, time.Minute)
}

func TestRealThumbnailCleanupTerminatesOnlyOwnedTaskQueue(t *testing.T) {
	address, namespace := os.Getenv("TEMPORAL_ADDRESS"), os.Getenv("TEMPORAL_NAMESPACE")
	if address == "" || namespace == "" {
		t.Fatal("TEMPORAL_ADDRESS and TEMPORAL_NAMESPACE are required for real thumbnail cleanup tests")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	databaseURL := testdb.New(t)
	database, err := postgres.NewPostgresDataSource(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	if err = database.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	source, err := temporaldata.NewTemporalDataSource(ctx, address, namespace, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	queue := "domabas-thumbnail-cleanup-" + uuid.NewString() + "-thumbnail"
	foreignQueue := queue + "-foreign"
	ownWorker := worker.New(source.Client(), queue, worker.Options{WorkerStopTimeout: time.Second})
	ownWorker.RegisterWorkflowWithOptions(thumbnailCleanupWait, workflow.RegisterOptions{Name: documentworkflows.DocumentThumbnailWorkflowName})
	if err = ownWorker.Start(); err != nil {
		t.Fatal(err)
	}
	defer ownWorker.Stop()
	starts := make(map[string]client.WorkflowRun)
	for _, taskQueue := range []string{queue, foreignQueue} {
		job, account, document := uuid.NewString(), uuid.NewString(), uuid.NewString()
		workflowID := "document-thumbnail-v1/" + job
		run, err := source.Client().ExecuteWorkflow(ctx, client.StartWorkflowOptions{ID: workflowID, TaskQueue: taskQueue, WorkflowExecutionTimeout: 2 * time.Minute, WorkflowIDReusePolicy: enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE}, documentworkflows.DocumentThumbnailWorkflowName, documentworkflows.DocumentThumbnailRequest{JobID: job, AccountID: account, DocumentID: document, SourceSHA256: strings.Repeat("a", 64), RendererRevision: 1, Attempt: 1})
		if err != nil {
			t.Fatal(err)
		}
		defer func() {
			cleanup, stop := context.WithTimeout(context.Background(), 5*time.Second)
			defer stop()
			_ = source.Client().TerminateWorkflow(cleanup, run.GetID(), run.GetRunID(), "owned cleanup regression fallback")
		}()
		starts[taskQueue] = run
		if _, err = connection.Exec(ctx, `INSERT INTO document_thumbnail_jobs(id,account_id,document_id,source_sha256,renderer_revision,workflow_id,run_id,task_queue,admitted_at) VALUES($1,$2,$3,$4,1,$5,$6,$7,clock_timestamp())`, job, account, document, strings.Repeat("a", 64), workflowID, run.GetRunID(), taskQueue); err != nil {
			t.Fatal(err)
		}
	}
	ownWorker.Stop()
	cleanupOwnedThumbnailExecutions(t, connection, source.Client(), queue)
	for _, taskQueue := range []string{queue, foreignQueue} {
		run := starts[taskQueue]
		description, err := source.Client().DescribeWorkflowExecution(ctx, run.GetID(), run.GetRunID())
		if err != nil {
			t.Fatal(err)
		}
		want := enumspb.WORKFLOW_EXECUTION_STATUS_TERMINATED
		if taskQueue == foreignQueue {
			want = enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING
		}
		if got := description.GetWorkflowExecutionInfo().GetStatus(); got != want {
			t.Fatalf("queue %s cleanup status=%s want=%s", taskQueue, got, want)
		}
	}
	cleanupOwnedThumbnailExecutions(t, connection, source.Client(), foreignQueue)
}
