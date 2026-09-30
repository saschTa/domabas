//go:build temporal

package temporal_test

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	enumspb "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
)

type thumbnailCleanupOwner struct {
	jobID, workflowID, runID, queue string
}

func thumbnailCleanupRun(owner thumbnailCleanupOwner, response *workflowservice.DescribeWorkflowExecutionResponse, queue string) (string, error) {
	job, err := uuid.Parse(owner.jobID)
	if err != nil || job == uuid.Nil || owner.workflowID != "document-thumbnail-v1/"+job.String() || owner.queue != queue {
		return "", errors.New("thumbnail cleanup ledger ownership does not match this test")
	}
	info := response.GetWorkflowExecutionInfo()
	execution := info.GetExecution()
	if execution.GetWorkflowId() != owner.workflowID || execution.GetRunId() == "" || (owner.runID != "" && execution.GetRunId() != owner.runID) || info.GetTaskQueue() != queue || info.GetType().GetName() != documentworkflows.DocumentThumbnailWorkflowName {
		return "", errors.New("thumbnail cleanup execution ownership does not match this test")
	}
	return execution.GetRunId(), nil
}

func cleanupOwnedThumbnailExecutions(t *testing.T, connection *pgx.Conn, remote client.Client, queue string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var available bool
	if err := connection.QueryRow(ctx, `SELECT to_regclass('document_thumbnail_jobs') IS NOT NULL`).Scan(&available); err != nil {
		t.Errorf("inspect thumbnail cleanup ledger: %v", err)
		return
	}
	if !available {
		return
	}
	cursor := "00000000-0000-0000-0000-000000000000"
	for {
		rows, err := connection.Query(ctx, `SELECT id::text,workflow_id,run_id,task_queue FROM document_thumbnail_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL AND id>$1::uuid AND task_queue=$2 ORDER BY id LIMIT 100`, cursor, queue)
		if err != nil {
			t.Errorf("read owned thumbnail executions: %v", err)
			return
		}
		var owners []thumbnailCleanupOwner
		for rows.Next() {
			var owner thumbnailCleanupOwner
			if err = rows.Scan(&owner.jobID, &owner.workflowID, &owner.runID, &owner.queue); err != nil {
				rows.Close()
				t.Errorf("read thumbnail execution identity: %v", err)
				return
			}
			owners = append(owners, owner)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			t.Errorf("read thumbnail execution page: %v", err)
			return
		}
		for _, owner := range owners {
			cursor = owner.jobID
			if owner.workflowID != "document-thumbnail-v1/"+owner.jobID || owner.queue != queue {
				t.Errorf("refuse thumbnail cleanup outside owned identity or task queue: %s", owner.jobID)
				continue
			}
			response, err := remote.DescribeWorkflowExecution(ctx, owner.workflowID, owner.runID)
			if err != nil {
				var missing *serviceerror.NotFound
				if !errors.As(err, &missing) {
					t.Errorf("inspect owned thumbnail execution: %v", err)
				}
				continue
			}
			run, err := thumbnailCleanupRun(owner, response, queue)
			if err != nil {
				t.Error(err)
				continue
			}
			if response.GetWorkflowExecutionInfo().GetStatus() != enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING {
				continue
			}
			if err = remote.TerminateWorkflow(ctx, owner.workflowID, run, "owned thumbnail ingestion test cleanup"); err != nil {
				t.Errorf("terminate owned thumbnail execution: %v", err)
				continue
			}
			closed, err := remote.DescribeWorkflowExecution(ctx, owner.workflowID, run)
			if err != nil {
				t.Errorf("verify thumbnail cleanup closure: %v", err)
				continue
			}
			if _, err = thumbnailCleanupRun(owner, closed, queue); err != nil {
				t.Error(err)
			} else if closed.GetWorkflowExecutionInfo().GetStatus() == enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING {
				t.Error(fmt.Errorf("owned thumbnail execution remains running after cleanup: %s", owner.jobID))
			}
		}
		if len(owners) < 100 {
			return
		}
	}
}
