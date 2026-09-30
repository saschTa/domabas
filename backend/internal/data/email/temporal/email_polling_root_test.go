package temporal

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"
	"go.temporal.io/sdk/activity"
	sdk "go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

func TestEmailPollStopsAtPageBoundaryAndBoundsRetries(t *testing.T) {
	for _, scenario := range []struct {
		name      string
		more      bool
		failure   error
		wantCalls int32
	}{
		{name: "mailbox_complete", wantCalls: 1},
		{name: "continuation_after_four_pages", more: true, wantCalls: 4},
		{name: "transient_retry_limit", failure: errors.New("mail server unavailable"), wantCalls: 2},
		{name: "authority_failure_no_retry", failure: sdk.NewNonRetryableApplicationError("authority_changed", "authority_changed", nil), wantCalls: 1},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var suite testsuite.WorkflowTestSuite
			environment := suite.NewTestWorkflowEnvironment()
			var calls atomic.Int32
			environment.RegisterWorkflowWithOptions(emailworkflows.EmailPollWorkflow, workflow.RegisterOptions{Name: emailworkflows.EmailPollWorkflowName})
			environment.RegisterActivityWithOptions(func(ctx context.Context, input emailworkflows.EmailPollPageInput) (m.EmailPageResult, error) {
				call := calls.Add(1)
				if input.RunID != "owned-run-id" || input.PageIndex < 0 || input.PageIndex > 3 {
					t.Error("activity lost bounded page identity")
				}
				if scenario.failure == nil && input.PageIndex != int(call)-1 {
					t.Error("workflow skipped or repeated a successful page")
				}
				if scenario.failure != nil && (input.PageIndex != 0 || activity.GetInfo(ctx).Attempt != call) {
					t.Error("retry changed page or attempt identity")
				}
				return m.EmailPageResult{HasMore: scenario.more}, scenario.failure
			}, activity.RegisterOptions{Name: emailworkflows.EmailPollPageActivityName})
			environment.ExecuteWorkflow(emailworkflows.EmailPollWorkflowName, emailworkflows.EmailPollWorkflowInput{RunID: "owned-run-id"})
			if !environment.IsWorkflowCompleted() || (environment.GetWorkflowError() != nil) != (scenario.failure != nil) || calls.Load() != scenario.wantCalls {
				t.Fatalf("bounded workflow failed: calls=%d err=%v", calls.Load(), environment.GetWorkflowError())
			}
			if scenario.failure == nil {
				var result emailworkflows.EmailPollWorkflowResult
				if err := environment.GetWorkflowResult(&result); err != nil || result.HasMore != scenario.more {
					t.Fatalf("continuation outcome: %+v %v", result, err)
				}
			}
		})
	}
}
