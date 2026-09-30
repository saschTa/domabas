package workflows

import (
	"time"

	sdk "go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

const PaperlessImportWorkflowName = "domabas.PaperlessImport.v1"

const PaperlessStepActivityName = "domabas.PaperlessStep.v1"

const PaperlessFailActivityName = "domabas.PaperlessFail.v1"

func PaperlessImportWorkflow(ctx workflow.Context, id string) error {
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: 90 * time.Second, ScheduleToCloseTimeout: 10 * time.Minute, RetryPolicy: &sdk.RetryPolicy{InitialInterval: 10 * time.Second, BackoffCoefficient: 2, MaximumInterval: 2 * time.Minute, MaximumAttempts: 4}})
	for i := 0; i < 100; i++ {
		var done bool
		if err := workflow.ExecuteActivity(ctx, PaperlessStepActivityName, id).Get(ctx, &done); err != nil {
			return workflow.ExecuteActivity(ctx, PaperlessFailActivityName, id).Get(ctx, nil)
		}
		if done {
			return nil
		}
		if err := workflow.Sleep(ctx, 100*time.Millisecond); err != nil {
			return err
		}
	}
	return workflow.NewContinueAsNewError(ctx, PaperlessImportWorkflowName, id)
}
