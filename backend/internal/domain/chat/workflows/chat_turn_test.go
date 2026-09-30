package workflows

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

func chatWorkflowTestEnvironment() *testsuite.TestWorkflowEnvironment {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterActivityWithOptions(func(context.Context, ChatTurnRequest) error { return nil }, activity.RegisterOptions{Name: RunChatTurnActivity})
	env.RegisterActivityWithOptions(func(context.Context, ChatStepRequest) (ChatStepResult, error) {
		return ChatStepResult{Completed: true}, nil
	}, activity.RegisterOptions{Name: RunChatStepActivity})
	env.RegisterActivityWithOptions(func(context.Context, ChatTurnFailure) error { return nil }, activity.RegisterOptions{Name: FailChatTurnActivity})
	return env
}

func TestChatWorkflowRunsDurableStepAndReturnsNoContent(t *testing.T) {
	env := chatWorkflowTestEnvironment()
	request := ChatTurnRequest{TurnID: "turn", AccountID: "account"}
	env.OnActivity(RunChatStepActivity, mock.Anything, ChatStepRequest{Request: request}).Return(ChatStepResult{Completed: true}, nil).Once()
	env.ExecuteWorkflow(ChatTurnWorkflow, request)
	if err := env.GetWorkflowError(); err != nil {
		t.Fatal(err)
	}
	var result ChatTurnResult
	if err := env.GetWorkflowResult(&result); err != nil || result.State != "completed" {
		t.Fatalf("result=%+v err=%v", result, err)
	}
	env.AssertExpectations(t)
}

func TestChatWorkflowPersistsTerminalProviderFailure(t *testing.T) {
	env := chatWorkflowTestEnvironment()
	request := ChatTurnRequest{TurnID: "turn", AccountID: "account"}
	env.OnActivity(RunChatStepActivity, mock.Anything, ChatStepRequest{Request: request}).Return(ChatStepResult{}, temporal.NewNonRetryableApplicationError("sanitized", "invalid_response", nil)).Once()
	env.OnActivity(FailChatTurnActivity, mock.Anything, ChatTurnFailure{Request: request, Code: "invalid_response"}).Return(nil).Once()
	env.ExecuteWorkflow(ChatTurnWorkflow, request)
	if err := env.GetWorkflowError(); err == nil {
		t.Fatal("failure was hidden")
	}
	env.AssertExpectations(t)
}

func TestChatWorkflowRetriesEachProviderRoundFourTimes(t *testing.T) {
	env := chatWorkflowTestEnvironment()
	request := ChatTurnRequest{TurnID: "turn", AccountID: "account"}
	for ordinal := 0; ordinal < 2; ordinal++ {
		step := ChatStepRequest{Request: request, Ordinal: ordinal}
		env.OnActivity(RunChatStepActivity, mock.Anything, step).Return(ChatStepResult{}, temporal.NewApplicationError("provider unavailable", "provider_unavailable")).Times(4)
		env.OnActivity(RunChatStepActivity, mock.Anything, step).Return(ChatStepResult{Completed: ordinal == 1}, nil).Once()
	}
	env.ExecuteWorkflow(ChatTurnWorkflow, request)
	if err := env.GetWorkflowError(); err != nil {
		t.Fatal(err)
	}
	env.AssertExpectations(t)
}

func TestChatWorkflowExhaustsEachStepAfterFiveAttempts(t *testing.T) {
	env := chatWorkflowTestEnvironment()
	request := ChatTurnRequest{TurnID: "turn", AccountID: "account"}
	env.OnActivity(RunChatStepActivity, mock.Anything, ChatStepRequest{Request: request}).Return(ChatStepResult{}, temporal.NewApplicationError("provider unavailable", "provider_unavailable")).Times(5)
	env.OnActivity(FailChatTurnActivity, mock.Anything, ChatTurnFailure{Request: request, Code: "provider_unavailable"}).Return(nil).Once()
	env.ExecuteWorkflow(ChatTurnWorkflow, request)
	if err := env.GetWorkflowError(); err == nil {
		t.Fatal("exhausted failure was hidden")
	}
	env.AssertExpectations(t)
}

func TestChatWorkflowLegacyBranchRetainsWholeTurnAndThreeAttempts(t *testing.T) {
	env := chatWorkflowTestEnvironment()
	request := ChatTurnRequest{TurnID: "turn", AccountID: "account"}
	env.OnGetVersion("chat-provider-four-retries", workflow.DefaultVersion, workflow.Version(1)).Return(workflow.DefaultVersion)
	env.OnActivity(RunChatTurnActivity, mock.Anything, request).Return(temporal.NewApplicationError("provider unavailable", "provider_unavailable")).Times(3)
	env.OnActivity(FailChatTurnActivity, mock.Anything, ChatTurnFailure{Request: request, Code: "provider_unavailable"}).Return(nil).Once()
	env.ExecuteWorkflow(ChatTurnWorkflow, request)
	if err := env.GetWorkflowError(); err == nil {
		t.Fatal("legacy retry limit changed")
	}
	env.AssertExpectations(t)
}
