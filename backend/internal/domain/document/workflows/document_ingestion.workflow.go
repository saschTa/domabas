package workflows

import (
	"errors"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

const (
	DocumentIngestionWorkflowName = "domabas.DocumentIngestion.v1"
	ExtractDocumentActivity       = "domabas.ExtractDocument.v1"
	InvoiceDocumentActivity       = "domabas.ExtractInvoice.v1"
	EnrichDocumentActivity        = "domabas.EnrichDocument.v1"
	EmbedDocumentActivity         = "domabas.EmbedDocument.v1"
	FinalizeDocumentActivity      = "domabas.FinalizeDocument.v1"
	FailDocumentActivity          = "domabas.FailDocument.v1"
)

func DocumentIngestionWorkflow(ctx workflow.Context, input DocumentIngestionRequest) (DocumentIngestionResult, error) {
	stageContext := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout:    4 * time.Minute,
		ScheduleToCloseTimeout: 15 * time.Minute,
		HeartbeatTimeout:       15 * time.Second,
		WaitForCancellation:    true,
		RetryPolicy: &temporal.RetryPolicy{
			InitialInterval: time.Second, BackoffCoefficient: 2,
			MaximumInterval: 5 * time.Second, MaximumAttempts: 3,
		},
	})
	stages := []string{ExtractDocumentActivity, EmbedDocumentActivity, FinalizeDocumentActivity}
	if workflow.GetVersion(ctx, "document-property-extraction", workflow.DefaultVersion, 1) != workflow.DefaultVersion {
		stages = []string{ExtractDocumentActivity, EnrichDocumentActivity, EmbedDocumentActivity, FinalizeDocumentActivity}
	}
	if workflow.GetVersion(ctx, "document-invoice-extraction", workflow.DefaultVersion, 1) != workflow.DefaultVersion {
		stages = append(stages[:1], append([]string{InvoiceDocumentActivity}, stages[1:]...)...)
	}
	timeoutVersion := workflow.GetVersion(ctx, "document-processing-timeouts", workflow.DefaultVersion, 2)
	for _, stage := range stages {
		options := workflow.GetActivityOptions(stageContext)
		policy := *options.RetryPolicy
		policy.MaximumAttempts = documentProviderAttempts(ctx, stage)
		options.RetryPolicy = &policy
		if input.UnlimitedInference {
			options.ScheduleToCloseTimeout = 0
			if stage == ExtractDocumentActivity && timeoutVersion >= 1 {
				options.StartToCloseTimeout = 8 * time.Minute
				if timeoutVersion >= 2 {
					options.StartToCloseTimeout = 16 * time.Minute
				}
			}
			if stage == ExtractDocumentActivity {
				options.StartToCloseTimeout = documentExtractionTimeout(ctx, options.StartToCloseTimeout)
			}
			if stage == InvoiceDocumentActivity || stage == EnrichDocumentActivity || stage == EmbedDocumentActivity {
				options.StartToCloseTimeout = 10 * 365 * 24 * time.Hour
			}
		}
		currentContext := workflow.WithActivityOptions(ctx, options)
		if err := workflow.ExecuteActivity(currentContext, stage, input).Get(currentContext, nil); err != nil {
			code := "processing_failed"
			var applicationError *temporal.ApplicationError
			if errors.As(err, &applicationError) {
				code = DocumentIngestionFailureCode(applicationError.Type())
			}
			if temporal.IsTimeoutError(err) {
				code = "processing_timeout"
			}
			cleanup, cancel := workflow.NewDisconnectedContext(ctx)
			cleanup = workflow.WithActivityOptions(cleanup, workflow.ActivityOptions{
				StartToCloseTimeout: 10 * time.Second, ScheduleToCloseTimeout: 30 * time.Second,
				RetryPolicy: &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 3},
			})
			_ = workflow.ExecuteActivity(cleanup, FailDocumentActivity, DocumentIngestionFailure{Job: input, Code: code}).Get(cleanup, nil)
			cancel()
			return DocumentIngestionResult{}, err
		}
	}
	return DocumentIngestionResult{State: "ready"}, nil
}

func DocumentIngestionFailureCode(code string) string {
	switch code {
	case "invalid_invoice", "invalid_classification", "output_limit", "empty_response", "response_too_large", "configuration_unavailable", "no_text", "invalid_file", "encrypted_pdf", "resource_limit", "processing_timeout", "delivery_timeout", "processing_incomplete", "processing_cancelled", "processing_terminated", "processing_failed", "inference_unavailable", "storage_unavailable":
		return code
	default:
		return "processing_failed"
	}
}
