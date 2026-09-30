package workflows

import (
	"errors"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
	"time"
)

const (
	DocumentSearchableWorkflowName = "domabas.DocumentIngestion.v2"
	DocumentAIWorkflowName         = "domabas.DocumentAI.v1"
	CompleteDocumentAIActivity     = "domabas.CompleteDocumentAI.v1"
	FailDocumentAIActivity         = "domabas.FailDocumentAI.v1"
)

func DocumentSearchableWorkflow(ctx workflow.Context, input DocumentIngestionRequest) (DocumentIngestionResult, error) {
	return documentStages(ctx, input, []string{ExtractDocumentActivity, EmbedDocumentActivity, FinalizeDocumentActivity}, FailDocumentActivity, "ready")
}

func DocumentAIWorkflow(ctx workflow.Context, input DocumentIngestionRequest) (DocumentIngestionResult, error) {
	if input.AIAttempt < 1 {
		return DocumentIngestionResult{}, temporal.NewNonRetryableApplicationError("invalid AI attempt", "invalid_job", nil)
	}
	return documentStages(ctx, input, []string{InvoiceDocumentActivity, EnrichDocumentActivity, CompleteDocumentAIActivity}, FailDocumentAIActivity, "succeeded")
}

func documentStages(ctx workflow.Context, input DocumentIngestionRequest, stages []string, failureActivity, result string) (DocumentIngestionResult, error) {
	for _, stage := range stages {
		timeout := 4 * time.Minute
		if stage == ExtractDocumentActivity {
			timeout = documentExtractionTimeout(ctx, 16*time.Minute)
		}
		if stage == InvoiceDocumentActivity || stage == EnrichDocumentActivity || stage == EmbedDocumentActivity {
			timeout = 10 * 365 * 24 * time.Hour
		}
		current := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: timeout, HeartbeatTimeout: 15 * time.Second, WaitForCancellation: true, RetryPolicy: &temporal.RetryPolicy{InitialInterval: time.Second, BackoffCoefficient: 2, MaximumInterval: 5 * time.Second, MaximumAttempts: documentProviderAttempts(ctx, stage)}})
		if err := workflow.ExecuteActivity(current, stage, input).Get(current, nil); err != nil {
			code := "processing_failed"
			var application *temporal.ApplicationError
			if errors.As(err, &application) {
				code = DocumentIngestionFailureCode(application.Type())
			}
			if temporal.IsTimeoutError(err) {
				code = "processing_timeout"
			}
			cleanup, cancel := workflow.NewDisconnectedContext(ctx)
			cleanup = workflow.WithActivityOptions(cleanup, workflow.ActivityOptions{StartToCloseTimeout: 10 * time.Second, ScheduleToCloseTimeout: 30 * time.Second, RetryPolicy: &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 3}})
			_ = workflow.ExecuteActivity(cleanup, failureActivity, DocumentIngestionFailure{Job: input, Code: code}).Get(cleanup, nil)
			cancel()
			return DocumentIngestionResult{}, err
		}
	}
	return DocumentIngestionResult{State: result}, nil
}
