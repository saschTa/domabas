package workflows

import (
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	sdk "go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

const EmailPollWorkflowName = "domabas.EmailPoll.v1"

const EmailPollPageActivityName = "domabas.EmailPollPage.v1"

func EmailPollWorkflow(ctx workflow.Context, input EmailPollWorkflowInput) (EmailPollWorkflowResult, error) {
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: 120 * time.Second, ScheduleToCloseTimeout: 150 * time.Second, HeartbeatTimeout: 10 * time.Second, RetryPolicy: &sdk.RetryPolicy{InitialInterval: time.Second, MaximumInterval: time.Second, MaximumAttempts: 2}})
	for page := 0; page < 4; page++ {
		var result m.EmailPageResult
		if err := workflow.ExecuteActivity(ctx, EmailPollPageActivityName, EmailPollPageInput{RunID: input.RunID, PageIndex: page}).Get(ctx, &result); err != nil {
			return EmailPollWorkflowResult{}, err
		}
		if !result.HasMore {
			return EmailPollWorkflowResult{}, nil
		}
	}
	return EmailPollWorkflowResult{HasMore: true}, nil
}
