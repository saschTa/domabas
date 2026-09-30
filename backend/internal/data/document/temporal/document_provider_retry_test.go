package temporal_test

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	w "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

func TestDocumentProviderStepsRetryFourTimesWithoutRepeatingOtherStages(t *testing.T) {
	for _, stage := range []string{w.EmbedDocumentActivity, w.InvoiceDocumentActivity, w.EnrichDocumentActivity} {
		for _, scenario := range []struct {
			name     string
			failures int32
			terminal bool
			legacy   bool
			want     int32
			failed   bool
		}{{"recovers on fifth", 4, false, false, 5, false}, {"exhausted", 8, false, false, 5, true}, {"terminal", 8, true, false, 1, true}, {"retained policy", 8, false, true, 3, true}} {
			t.Run(fmt.Sprintf("%s/%s", stage, scenario.name), func(t *testing.T) {
				var suite testsuite.WorkflowTestSuite
				env := suite.NewTestWorkflowEnvironment()
				if scenario.legacy {
					env.OnGetVersion("document-provider-four-retries", workflow.DefaultVersion, workflow.Version(1)).Return(workflow.DefaultVersion)
				}
				counts := make(map[string]*atomic.Int32)
				for _, name := range []string{w.ExtractDocumentActivity, w.EmbedDocumentActivity, w.FinalizeDocumentActivity, w.InvoiceDocumentActivity, w.EnrichDocumentActivity, w.CompleteDocumentAIActivity} {
					counts[name] = &atomic.Int32{}
					env.RegisterActivityWithOptions(func(context.Context, w.DocumentIngestionRequest) error {
						attempt := counts[name].Add(1)
						if name == stage && attempt <= scenario.failures {
							return temporal.NewApplicationErrorWithOptions("provider busy", "inference_unavailable", temporal.ApplicationErrorOptions{NonRetryable: scenario.terminal, NextRetryDelay: 65 * time.Second})
						}
						return nil
					}, activity.RegisterOptions{Name: name})
				}
				var failed atomic.Int32
				for _, name := range []string{w.FailDocumentActivity, w.FailDocumentAIActivity} {
					env.RegisterActivityWithOptions(func(_ context.Context, failure w.DocumentIngestionFailure) error {
						if failure.Code != "inference_unavailable" {
							t.Errorf("unexpected failure: %+v", failure)
						}
						failed.Add(1)
						return nil
					}, activity.RegisterOptions{Name: name})
				}
				input := w.DocumentIngestionRequest{Generation: 1, AIAttempt: 1, UnlimitedInference: true}
				if stage == w.EmbedDocumentActivity {
					env.ExecuteWorkflow(w.DocumentSearchableWorkflow, input)
				} else {
					env.ExecuteWorkflow(w.DocumentAIWorkflow, input)
				}
				if counts[stage].Load() != scenario.want || (env.GetWorkflowError() != nil) != scenario.failed || (failed.Load() == 1) != scenario.failed {
					t.Fatalf("attempts=%d cleanup=%d error=%v", counts[stage].Load(), failed.Load(), env.GetWorkflowError())
				}
				for name, count := range counts {
					if name != stage && count.Load() > 1 {
						t.Fatalf("successful stage repeated: %s", name)
					}
				}
			})
		}
	}
}
