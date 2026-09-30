package workflows

import (
	"errors"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

const (
	ChatTurnWorkflowName = "domabas.ChatTurn.v1"
	RunChatTurnActivity  = "domabas.RunChatTurn.v1"
	RunChatStepActivity  = "domabas.RunChatStep.v1"
	FailChatTurnActivity = "domabas.FailChatTurn.v1"
)

func ChatTurnWorkflow(ctx workflow.Context, input ChatTurnRequest) (ChatTurnResult, error) {
	maximumAttempts := int32(3)
	stepRetries := workflow.GetVersion(ctx, "chat-provider-four-retries", workflow.DefaultVersion, 1) != workflow.DefaultVersion
	if stepRetries {
		maximumAttempts = 5
	}
	run := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout: 24 * time.Hour,
		HeartbeatTimeout:    15 * time.Second,
		WaitForCancellation: true,
		RetryPolicy:         &temporal.RetryPolicy{InitialInterval: 190 * time.Second, BackoffCoefficient: 1, MaximumInterval: 190 * time.Second, MaximumAttempts: maximumAttempts},
	})
	var err error
	if stepRetries {
		err = runChatSteps(run, input)
	} else {
		err = workflow.ExecuteActivity(run, RunChatTurnActivity, input).Get(run, nil)
	}
	if err == nil {
		return ChatTurnResult{State: "completed"}, nil
	}
	code := "chat_failed"
	var failure *temporal.ApplicationError
	if errors.As(err, &failure) {
		code = ChatFailureCode(failure.Type())
	}
	if temporal.IsTimeoutError(err) {
		code = "chat_timeout"
	}
	if temporal.IsCanceledError(err) {
		code = "chat_cancelled"
	}
	cleanup, cancel := workflow.NewDisconnectedContext(ctx)
	defer cancel()
	cleanup = workflow.WithActivityOptions(cleanup, workflow.ActivityOptions{
		StartToCloseTimeout:    10 * time.Second,
		ScheduleToCloseTimeout: 30 * time.Second,
		RetryPolicy:            &temporal.RetryPolicy{InitialInterval: time.Second, MaximumAttempts: 3},
	})
	_ = workflow.ExecuteActivity(cleanup, FailChatTurnActivity, ChatTurnFailure{Request: input, Code: code}).Get(cleanup, nil)
	return ChatTurnResult{}, err
}

func runChatSteps(ctx workflow.Context, input ChatTurnRequest) error {
	for ordinal := 0; ordinal <= m.ChatMaxToolCalls; ordinal++ {
		var result ChatStepResult
		err := workflow.ExecuteActivity(ctx, RunChatStepActivity, ChatStepRequest{Request: input, Ordinal: ordinal}).Get(ctx, &result)
		if err != nil || result.Completed {
			return err
		}
	}
	return temporal.NewNonRetryableApplicationError("chat tool budget exhausted", "tool_limit", nil)
}

func ChatFailureCode(code string) string {
	switch code {
	case "chat_failed", "chat_timeout", "chat_cancelled", "provider_unavailable", "provider_rejected", "invalid_response", "output_limit", "empty_response", "tool_limit", "access_revoked", "configuration_unavailable", "delivery_timeout", "execution_lost", "execution_busy", "document_unavailable", "resource_limit":
		return code
	default:
		return "chat_failed"
	}
}
