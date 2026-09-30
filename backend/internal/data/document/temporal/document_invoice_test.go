package temporal_test

import (
	"context"
	"strings"
	"testing"

	adapter "github.com/domabas/domabas/backend/internal/data/document/temporal"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

func TestInvoiceActivityVersioningAndTerminalFailure(t *testing.T) {
	for _, scenario := range []struct {
		name    string
		version workflow.Version
		fail    bool
		want    string
	}{{"retained", workflow.DefaultVersion, false, "extract,enrich,embed,finalize"}, {"new", 1, false, "extract,invoice,enrich,embed,finalize"}, {"invalid XML", 1, true, "extract,invoice,fail"}} {
		t.Run(scenario.name, func(t *testing.T) {
			var calls []string
			s := &ingestionService{extract: func(context.Context, document.DocumentJob) error { calls = append(calls, "extract"); return nil }, invoice: func(context.Context, document.DocumentJob) error {
				calls = append(calls, "invoice")
				if scenario.fail {
					return document.DocumentProcessingError{Code: "invalid_invoice"}
				}
				return nil
			}, enrich: func(context.Context, document.DocumentJob) error { calls = append(calls, "enrich"); return nil }, embed: func(context.Context, document.DocumentJob) error { calls = append(calls, "embed"); return nil }, finalize: func(context.Context, document.DocumentJob) error { calls = append(calls, "finalize"); return nil }, fail: func(_ context.Context, _ document.DocumentJob, code string) error {
				calls = append(calls, "fail")
				if code != "invalid_invoice" {
					t.Fatal(code)
				}
				return nil
			}}
			a := adapter.NewDocumentIngestionActivities(s, s, s)
			defer a.Close()
			var suite testsuite.WorkflowTestSuite
			env := suite.NewTestWorkflowEnvironment()
			env.OnGetVersion("document-invoice-extraction", workflow.DefaultVersion, workflow.Version(1)).Return(scenario.version)
			env.RegisterActivityWithOptions(a.Extract, activity.RegisterOptions{Name: documentworkflows.ExtractDocumentActivity})
			env.RegisterActivityWithOptions(a.Invoice, activity.RegisterOptions{Name: documentworkflows.InvoiceDocumentActivity})
			env.RegisterActivityWithOptions(a.Enrich, activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
			env.RegisterActivityWithOptions(a.Embed, activity.RegisterOptions{Name: documentworkflows.EmbedDocumentActivity})
			env.RegisterActivityWithOptions(a.Finalize, activity.RegisterOptions{Name: documentworkflows.FinalizeDocumentActivity})
			env.RegisterActivityWithOptions(a.Fail, activity.RegisterOptions{Name: documentworkflows.FailDocumentActivity})
			env.ExecuteWorkflow(documentworkflows.DocumentIngestionWorkflow, documentworkflows.DocumentIngestionRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 1})
			if strings.Join(calls, ",") != scenario.want || (env.GetWorkflowError() != nil) != scenario.fail {
				t.Fatalf("%v: %v", calls, env.GetWorkflowError())
			}
		})
	}
}
