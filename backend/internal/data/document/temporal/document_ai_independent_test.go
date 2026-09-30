package temporal_test

import (
	"context"
	"reflect"
	"sync"
	"testing"

	adapter "github.com/domabas/domabas/backend/internal/data/document/temporal"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
)

func TestSearchableWorkflowFinishesWithoutOptionalActivities(t *testing.T) {
	for _, scenario := range []struct {
		name      string
		embedFail bool
		want      []string
	}{
		{name: "AI unavailable", want: []string{"extract", "embed", "publish"}},
		{name: "mandatory failure remains visible", embedFail: true, want: []string{"extract", "embed", "fail ingestion"}},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var mutex sync.Mutex
			var calls []string
			record := func(value string) {
				mutex.Lock()
				defer mutex.Unlock()
				calls = append(calls, value)
			}
			service := &ingestionService{
				extract: func(context.Context, document.DocumentJob) error {
					record("extract")
					return nil
				},
				embed: func(context.Context, document.DocumentJob) error {
					record("embed")
					if scenario.embedFail {
						return document.DocumentProcessingError{Code: "configuration_unavailable"}
					}
					return nil
				},
				finalize: func(context.Context, document.DocumentJob) error {
					record("publish")
					return nil
				},
				invoice: func(context.Context, document.DocumentJob) error {
					record("unexpected invoice AI")
					return document.DocumentProcessingError{Code: "inference_unavailable"}
				},
				enrich: func(context.Context, document.DocumentJob) error {
					record("unexpected property AI")
					return document.DocumentProcessingError{Code: "inference_unavailable"}
				},
				fail: func(_ context.Context, _ document.DocumentJob, code string) error {
					record("fail ingestion")
					if code != "configuration_unavailable" {
						t.Errorf("mandatory failure code=%q", code)
					}
					return nil
				},
			}
			activities := adapter.NewDocumentIngestionActivities(service, service, service)
			t.Cleanup(activities.Close)
			var suite testsuite.WorkflowTestSuite
			environment := suite.NewTestWorkflowEnvironment()
			environment.RegisterActivityWithOptions(activities.Extract, activity.RegisterOptions{Name: documentworkflows.ExtractDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Embed, activity.RegisterOptions{Name: documentworkflows.EmbedDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Finalize, activity.RegisterOptions{Name: documentworkflows.FinalizeDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Invoice, activity.RegisterOptions{Name: documentworkflows.InvoiceDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Enrich, activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Fail, activity.RegisterOptions{Name: documentworkflows.FailDocumentActivity})
			environment.ExecuteWorkflow(documentworkflows.DocumentSearchableWorkflow, documentworkflows.DocumentIngestionRequest{
				AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 1, UnlimitedInference: true,
			})
			if !environment.IsWorkflowCompleted() || (environment.GetWorkflowError() != nil) != scenario.embedFail {
				t.Fatalf("mandatory pipeline outcome: %v", environment.GetWorkflowError())
			}
			mutex.Lock()
			defer mutex.Unlock()
			if !reflect.DeepEqual(calls, scenario.want) {
				t.Fatalf("mandatory pipeline ran optional work or changed order: %v", calls)
			}
			if !scenario.embedFail {
				var result documentworkflows.DocumentIngestionResult
				if err := environment.GetWorkflowResult(&result); err != nil || result.State != "ready" {
					t.Fatalf("ingestion did not complete as ready: %+v %v", result, err)
				}
			}
		})
	}
}

func TestAIWorkflowFailureUsesOnlyAIAttemptOwnership(t *testing.T) {
	for _, scenario := range []struct {
		name, failAt string
		want         []string
	}{
		{name: "invoice unavailable", failAt: "invoice", want: []string{"invoice", "fail AI"}},
		{name: "properties unavailable", failAt: "properties", want: []string{"invoice", "properties", "fail AI"}},
		{name: "AI complete", want: []string{"invoice", "properties", "complete AI"}},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			input := documentworkflows.DocumentIngestionRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 4, AIAttempt: 2, UnlimitedInference: true}
			var mutex sync.Mutex
			var calls []string
			record := func(value string) {
				mutex.Lock()
				defer mutex.Unlock()
				calls = append(calls, value)
			}
			stage := func(name string) func(context.Context, documentworkflows.DocumentIngestionRequest) error {
				return func(_ context.Context, request documentworkflows.DocumentIngestionRequest) error {
					if request != input {
						t.Errorf("AI stage changed attempt ownership: %+v", request)
					}
					record(name)
					if name == scenario.failAt {
						return temporal.NewNonRetryableApplicationError("optional provider unavailable", "inference_unavailable", nil)
					}
					return nil
				}
			}
			var suite testsuite.WorkflowTestSuite
			environment := suite.NewTestWorkflowEnvironment()
			environment.RegisterActivityWithOptions(stage("invoice"), activity.RegisterOptions{Name: documentworkflows.InvoiceDocumentActivity})
			environment.RegisterActivityWithOptions(stage("properties"), activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
			environment.RegisterActivityWithOptions(stage("complete AI"), activity.RegisterOptions{Name: documentworkflows.CompleteDocumentAIActivity})
			environment.RegisterActivityWithOptions(func(_ context.Context, failure documentworkflows.DocumentIngestionFailure) error {
				record("fail AI")
				if failure.Job != input || failure.Code != "inference_unavailable" {
					t.Errorf("AI failure lost attempt ownership or failure: %+v", failure)
				}
				return nil
			}, activity.RegisterOptions{Name: documentworkflows.FailDocumentAIActivity})
			environment.RegisterActivityWithOptions(func(context.Context, documentworkflows.DocumentIngestionFailure) error {
				t.Error("AI failure attempted to fail ingestion")
				return nil
			}, activity.RegisterOptions{Name: documentworkflows.FailDocumentActivity})
			environment.ExecuteWorkflow(documentworkflows.DocumentAIWorkflow, input)
			if !environment.IsWorkflowCompleted() || (environment.GetWorkflowError() != nil) != (scenario.failAt != "") {
				t.Fatalf("unexpected AI outcome: %v", environment.GetWorkflowError())
			}
			mutex.Lock()
			defer mutex.Unlock()
			if !reflect.DeepEqual(calls, scenario.want) {
				t.Fatalf("AI pipeline crossed ingestion or ran wrong stages: %v", calls)
			}
		})
	}
}
