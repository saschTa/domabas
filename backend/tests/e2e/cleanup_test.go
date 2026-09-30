//go:build e2e

package e2e_test

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	enumspb "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
)

func cleanupOwnedIngestion(t *testing.T, databaseURL, queue string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	connection, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		t.Errorf("connect for owned ingestion cleanup: %v", err)
		return
	}
	defer connection.Close(ctx)
	rows, err := connection.Query(ctx, `SELECT workflow_id,run_id,task_queue,CASE WHEN split_pipeline THEN 'domabas.DocumentIngestion.v2' ELSE 'domabas.DocumentIngestion.v1' END
FROM document_processing_executions WHERE closed_at IS NULL
UNION ALL
SELECT workflow_id,run_id,task_queue,'domabas.DocumentAI.v1' FROM document_ai_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL
UNION ALL
SELECT workflow_id,run_id,task_queue,'domabas.DocumentThumbnail.v1' FROM document_thumbnail_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL
UNION ALL
SELECT workflow_id,run_id,task_queue,'domabas.ChatTurn.v1' FROM chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed`)
	if err != nil {
		var databaseError *pgconn.PgError
		if !errors.As(err, &databaseError) || databaseError.Code != "42P01" {
			t.Errorf("read owned ingestion jobs: %v", err)
		}
		return
	}
	type ownedDocumentExecution struct {
		workflowID, runID, taskQueue, workflowType string
	}
	var jobs []ownedDocumentExecution
	for rows.Next() {
		var job ownedDocumentExecution
		if err := rows.Scan(&job.workflowID, &job.runID, &job.taskQueue, &job.workflowType); err != nil {
			rows.Close()
			t.Errorf("read owned ingestion identity: %v", err)
			return
		}
		jobs = append(jobs, job)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		t.Errorf("read owned ingestion jobs: %v", err)
		return
	}
	if len(jobs) == 0 {
		return
	}
	remote, err := client.DialContext(ctx, client.Options{HostPort: os.Getenv("TEMPORAL_ADDRESS"), Namespace: os.Getenv("TEMPORAL_NAMESPACE")})
	if err != nil {
		t.Errorf("connect for owned workflow cleanup: %v", err)
		return
	}
	defer remote.Close()
	for _, job := range jobs {
		expectedQueue := queue
		switch job.workflowType {
		case documentworkflows.DocumentIngestionWorkflowName, "domabas.DocumentIngestion.v2":
		case "domabas.DocumentAI.v1":
			expectedQueue += "-ai"
		case "domabas.DocumentThumbnail.v1":
			expectedQueue += "-thumbnail"
		case "domabas.ChatTurn.v1":
			expectedQueue += "-chat"
		default:
			t.Error("unknown workflow type in disposable schema; left untouched")
			continue
		}
		if job.taskQueue != expectedQueue || job.workflowID == "" {
			t.Error("workflow record does not belong to disposable queue; left untouched")
			continue
		}
		info, err := remote.DescribeWorkflowExecution(ctx, job.workflowID, job.runID)
		var missing *serviceerror.NotFound
		if errors.As(err, &missing) {
			continue
		}
		if err != nil {
			t.Errorf("inspect owned workflow: %v", err)
			continue
		}
		execution := info.GetWorkflowExecutionInfo()
		actual := execution.GetExecution()
		if execution.GetTaskQueue() != job.taskQueue || execution.GetType().GetName() != job.workflowType || actual.GetWorkflowId() != job.workflowID || actual.GetRunId() == "" || (job.runID != "" && actual.GetRunId() != job.runID) {
			t.Error("owned document ID unexpectedly belongs to another workflow; left untouched")
			continue
		}
		if execution.GetStatus() != enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING {
			continue
		}
		if err := remote.TerminateWorkflow(ctx, job.workflowID, actual.GetRunId(), "owned API document test cleanup"); err != nil && !errors.As(err, &missing) {
			t.Errorf("terminate owned document workflow: %v", err)
		}
	}
}
