package workflows

import (
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
	"time"
)

const (
	DocumentThumbnailWorkflowName   = "domabas.DocumentThumbnail.v1"
	RenderDocumentThumbnailActivity = "domabas.RenderDocumentThumbnail.v1"
	FinishDocumentThumbnailActivity = "domabas.FinishDocumentThumbnail.v1"
)

func DocumentThumbnailWorkflow(ctx workflow.Context, input DocumentThumbnailRequest) error {
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: 2 * time.Minute, ScheduleToCloseTimeout: 5 * time.Minute, HeartbeatTimeout: 20 * time.Second, RetryPolicy: &temporal.RetryPolicy{InitialInterval: 2 * time.Second, BackoffCoefficient: 2, MaximumInterval: 30 * time.Second, MaximumAttempts: 3}})
	var result DocumentThumbnailResult
	err := workflow.ExecuteActivity(ctx, RenderDocumentThumbnailActivity, input).Get(ctx, &result)
	if err != nil {
		result = DocumentThumbnailResult{FailureCode: "thumbnail_unavailable", Retryable: true}
	}
	if result.FailureCode != "" {
		cleanup, _ := workflow.NewDisconnectedContext(ctx)
		cleanup = workflow.WithActivityOptions(cleanup, workflow.ActivityOptions{StartToCloseTimeout: 15 * time.Second, ScheduleToCloseTimeout: time.Minute, RetryPolicy: &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 3}})
		if finishErr := workflow.ExecuteActivity(cleanup, FinishDocumentThumbnailActivity, DocumentThumbnailFailure{Request: input, Outcome: result}).Get(cleanup, nil); finishErr != nil {
			return finishErr
		}
	}
	return err
}
