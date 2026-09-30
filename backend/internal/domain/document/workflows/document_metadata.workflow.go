package workflows

import (
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

const (
	DocumentMetadataWorkflowName       = "domabas.DocumentMetadata.v2"
	ReadDocumentMetadataActivity       = "domabas.ReadDocumentMetadata.v2"
	LegacyDocumentMetadataWorkflowName = "domabas.DocumentMetadata.v1"
	LegacyReadDocumentMetadataActivity = "domabas.ReadDocumentMetadata.v1"
)

func DocumentMetadataWorkflow(ctx workflow.Context, input DocumentMetadataRequest) (DocumentMetadataResult, error) {
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout:    10 * time.Second,
		ScheduleToCloseTimeout: 40 * time.Second,
		RetryPolicy: &temporal.RetryPolicy{
			InitialInterval: time.Second, BackoffCoefficient: 2,
			MaximumInterval: 5 * time.Second, MaximumAttempts: 3,
		},
	})
	var metadata DocumentMetadataResult
	err := workflow.ExecuteActivity(ctx, ReadDocumentMetadataActivity, input).Get(ctx, &metadata)
	return metadata, err
}

func LegacyDocumentMetadataWorkflow(ctx workflow.Context, documentID string) (DocumentMetadataResult, error) {
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout:    10 * time.Second,
		ScheduleToCloseTimeout: 40 * time.Second,
		RetryPolicy: &temporal.RetryPolicy{
			InitialInterval: time.Second, BackoffCoefficient: 2,
			MaximumInterval: 5 * time.Second, MaximumAttempts: 3,
		},
	})
	var metadata DocumentMetadataResult
	err := workflow.ExecuteActivity(ctx, LegacyReadDocumentMetadataActivity, documentID).Get(ctx, &metadata)
	return metadata, err
}
