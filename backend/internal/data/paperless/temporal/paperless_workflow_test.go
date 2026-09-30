package temporal

import (
	"context"
	"errors"
	"testing"

	paperlessworkflows "github.com/domabas/domabas/backend/internal/domain/paperless/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"
)

func TestPipelineRetriesStepsAndRecordsExhaustion(t *testing.T) {
	for _, exhaust := range []bool{false, true} {
		var suite testsuite.WorkflowTestSuite
		env := suite.NewTestWorkflowEnvironment()
		calls, failed := 0, false
		env.RegisterActivityWithOptions(func(context.Context, string) (bool, error) {
			calls++
			if exhaust || calls == 1 {
				return false, errors.New("source offline")
			}
			return true, nil
		}, activity.RegisterOptions{Name: paperlessworkflows.PaperlessStepActivityName})
		env.RegisterActivityWithOptions(func(context.Context, string) error { failed = true; return nil }, activity.RegisterOptions{Name: paperlessworkflows.PaperlessFailActivityName})
		env.ExecuteWorkflow(paperlessworkflows.PaperlessImportWorkflow, "test-owned-run")
		if !env.IsWorkflowCompleted() || env.GetWorkflowError() != nil || failed != exhaust {
			t.Fatal(env.GetWorkflowError(), calls, failed)
		}
		if exhaust && calls != 4 || !exhaust && calls != 2 {
			t.Fatalf("unexpected bounded retries: %d", calls)
		}
	}
}
