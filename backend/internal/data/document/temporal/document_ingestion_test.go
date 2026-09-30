package temporal_test

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"

	adapter "github.com/domabas/domabas/backend/internal/data/document/temporal"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"
)

type ingestionService struct {
	invoice  func(context.Context, document.DocumentJob) error
	enrich   func(context.Context, document.DocumentJob) error
	extract  func(context.Context, document.DocumentJob) error
	embed    func(context.Context, document.DocumentJob) error
	finalize func(context.Context, document.DocumentJob) error
	fail     func(context.Context, document.DocumentJob, string) error
}

func (service *ingestionService) ExtractInvoice(ctx context.Context, job document.DocumentJob) error {
	if service.invoice != nil {
		return service.invoice(ctx, job)
	}
	return nil
}

func (service *ingestionService) Extract(ctx context.Context, job document.DocumentJob) error {
	return service.extract(ctx, job)
}

func (service *ingestionService) Enrich(ctx context.Context, job document.DocumentJob) error {
	if service.enrich != nil {
		return service.enrich(ctx, job)
	}
	return nil
}

func (service *ingestionService) Embed(ctx context.Context, job document.DocumentJob) error {
	return service.embed(ctx, job)
}

func (service *ingestionService) Finalize(ctx context.Context, job document.DocumentJob) error {
	return service.finalize(ctx, job)
}

func (service *ingestionService) Fail(ctx context.Context, job document.DocumentJob, code string) error {
	return service.fail(ctx, job, code)
}

func TestIngestionStagesRetryAndSanitizeFailures(t *testing.T) {
	input := documentworkflows.DocumentIngestionRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 2}
	for _, scenario := range []struct {
		name      string
		failure   error
		failCount int32
		wantCalls int32
		wantCode  string
	}{
		{name: "success", wantCalls: 1},
		{name: "transient retry", failure: errors.New("SECRET OCR TEXT /private/storage postgres://password"), failCount: 2, wantCalls: 3},
		{name: "busy CPU processor", failure: document.ErrOverloaded, failCount: 2, wantCalls: 3},
		{name: "persistent failure", failure: errors.New("SECRET OCR TEXT /private/storage postgres://password"), failCount: 9, wantCalls: 3, wantCode: "processing_failed"},
		{name: "no text", failure: document.DocumentProcessingError{Code: "no_text"}, failCount: 9, wantCalls: 1, wantCode: "no_text"},
		{name: "unknown processor error", failure: document.DocumentProcessingError{Code: "SECRET OCR TEXT"}, failCount: 9, wantCalls: 1, wantCode: "processing_failed"},
		{name: "stale generation", failure: document.ErrStaleJob, failCount: 9, wantCalls: 1, wantCode: "processing_failed"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var extractCalls, embedded, finalized, failures atomic.Int32
			check := func(job document.DocumentJob) {
				if job.AccountID != input.AccountID || job.DocumentID != input.DocumentID || job.Generation != input.Generation {
					t.Errorf("stage changed job scope: %+v", job)
				}
			}
			service := &ingestionService{
				extract: func(_ context.Context, job document.DocumentJob) error {
					check(job)
					if extractCalls.Add(1) <= scenario.failCount {
						return scenario.failure
					}
					return nil
				},
				embed:    func(_ context.Context, job document.DocumentJob) error { check(job); embedded.Add(1); return nil },
				finalize: func(_ context.Context, job document.DocumentJob) error { check(job); finalized.Add(1); return nil },
				fail: func(_ context.Context, job document.DocumentJob, code string) error {
					check(job)
					failures.Add(1)
					if code != scenario.wantCode {
						t.Errorf("failure code %q, want %q", code, scenario.wantCode)
					}
					return nil
				},
			}
			activities := adapter.NewDocumentIngestionActivities(service, service, service)
			defer activities.Close()
			var suite testsuite.WorkflowTestSuite
			environment := suite.NewTestWorkflowEnvironment()
			environment.RegisterWorkflowWithOptions(documentworkflows.DocumentIngestionWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentIngestionWorkflowName})
			environment.RegisterActivityWithOptions(activities.Extract, activity.RegisterOptions{Name: documentworkflows.ExtractDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Invoice, activity.RegisterOptions{Name: documentworkflows.InvoiceDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Enrich, activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Embed, activity.RegisterOptions{Name: documentworkflows.EmbedDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Finalize, activity.RegisterOptions{Name: documentworkflows.FinalizeDocumentActivity})
			environment.RegisterActivityWithOptions(activities.Fail, activity.RegisterOptions{Name: documentworkflows.FailDocumentActivity})
			environment.ExecuteWorkflow(documentworkflows.DocumentIngestionWorkflowName, input)
			err := environment.GetWorkflowError()
			if !environment.IsWorkflowCompleted() || (err != nil) != (scenario.wantCode != "") {
				t.Fatalf("unexpected workflow result: %v", err)
			}
			if err != nil && (strings.Contains(err.Error(), "SECRET") || strings.Contains(err.Error(), "postgres://") || strings.Contains(err.Error(), "/private/")) {
				t.Fatal("private dependency failure reached workflow history")
			}
			if extractCalls.Load() != scenario.wantCalls {
				t.Fatalf("extraction attempts %d, want %d", extractCalls.Load(), scenario.wantCalls)
			}
			if scenario.wantCode == "" {
				var result documentworkflows.DocumentIngestionResult
				if err := environment.GetWorkflowResult(&result); err != nil || result.State != "ready" || embedded.Load() != 1 || finalized.Load() != 1 || failures.Load() != 0 {
					t.Fatalf("incomplete successful pipeline: %+v %v", result, err)
				}
			} else if embedded.Load() != 0 || finalized.Load() != 0 || failures.Load() != 1 {
				t.Fatal("failed extraction continued processing or omitted compensation")
			}
		})
	}
}

func TestIngestionCloseDrainsAndAllowsRestartRetry(t *testing.T) {
	entered, released := make(chan struct{}), make(chan struct{})
	activities := adapter.NewDocumentIngestionActivities(&ingestionService{extract: func(ctx context.Context, _ document.DocumentJob) error {
		close(entered)
		<-ctx.Done()
		close(released)
		return ctx.Err()
	}}, &ingestionService{}, &ingestionService{})
	input := documentworkflows.DocumentIngestionRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 1}
	done := make(chan error, 1)
	go func() { done <- activities.Extract(t.Context(), input) }()
	<-entered
	activities.Close()
	select {
	case <-released:
	default:
		t.Fatal("close returned before active processing released resources")
	}
	var failure *temporal.ApplicationError
	if err := <-done; !errors.As(err, &failure) || failure.NonRetryable() {
		t.Fatalf("worker shutdown must permit the durable job to retry: %v", err)
	}
	if err := activities.Extract(t.Context(), input); !errors.Is(err, context.Canceled) {
		t.Fatalf("closed activity accepted new work: %v", err)
	}
}

func TestInvalidIngestionScopeNeverReachesService(t *testing.T) {
	activities := adapter.NewDocumentIngestionActivities(&ingestionService{extract: func(context.Context, document.DocumentJob) error {
		t.Fatal("invalid scope reached ingestion service")
		return nil
	}}, &ingestionService{}, &ingestionService{})
	defer activities.Close()
	for _, input := range []documentworkflows.DocumentIngestionRequest{
		{},
		{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 0},
		{AccountID: "00000000-0000-0000-0000-000000000000", DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 1},
	} {
		var failure *temporal.ApplicationError
		if err := activities.Extract(t.Context(), input); !errors.As(err, &failure) || !failure.NonRetryable() {
			t.Fatalf("invalid job was not rejected permanently: %v", err)
		}
	}
}

func TestPropertyExtractionVersioningOrderAndFailures(t *testing.T) {
	for _, scenario := range []struct {
		name    string
		version workflow.Version
		failure bool
		want    string
	}{
		{"retained workflow", workflow.DefaultVersion, false, "extract,embed,finalize"},
		{"new workflow", 1, false, "extract,enrich,embed,finalize"},
		{"failed enrichment", 1, true, "extract,enrich,fail"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var calls []string
			service := &ingestionService{
				extract: func(context.Context, document.DocumentJob) error { calls = append(calls, "extract"); return nil },
				enrich: func(context.Context, document.DocumentJob) error {
					calls = append(calls, "enrich")
					if scenario.failure {
						return document.DocumentProcessingError{Code: "configuration_unavailable"}
					}
					return nil
				},
				embed:    func(context.Context, document.DocumentJob) error { calls = append(calls, "embed"); return nil },
				finalize: func(context.Context, document.DocumentJob) error { calls = append(calls, "finalize"); return nil },
				fail: func(_ context.Context, _ document.DocumentJob, code string) error {
					calls = append(calls, "fail")
					if code != "configuration_unavailable" {
						t.Error(code)
					}
					return nil
				},
			}
			activities := adapter.NewDocumentIngestionActivities(service, service, service)
			defer activities.Close()
			var suite testsuite.WorkflowTestSuite
			env := suite.NewTestWorkflowEnvironment()
			env.OnGetVersion("document-invoice-extraction", workflow.DefaultVersion, workflow.Version(1)).Return(workflow.DefaultVersion)
			env.OnGetVersion("document-property-extraction", workflow.DefaultVersion, workflow.Version(1)).Return(scenario.version)
			env.RegisterActivityWithOptions(activities.Extract, activity.RegisterOptions{Name: documentworkflows.ExtractDocumentActivity})
			env.RegisterActivityWithOptions(activities.Enrich, activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
			env.RegisterActivityWithOptions(activities.Embed, activity.RegisterOptions{Name: documentworkflows.EmbedDocumentActivity})
			env.RegisterActivityWithOptions(activities.Finalize, activity.RegisterOptions{Name: documentworkflows.FinalizeDocumentActivity})
			env.RegisterActivityWithOptions(activities.Fail, activity.RegisterOptions{Name: documentworkflows.FailDocumentActivity})
			env.ExecuteWorkflow(documentworkflows.DocumentIngestionWorkflow, documentworkflows.DocumentIngestionRequest{AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 1})
			if strings.Join(calls, ",") != scenario.want || (env.GetWorkflowError() != nil) != scenario.failure {
				t.Fatalf("calls %v result %v", calls, env.GetWorkflowError())
			}
		})
	}
}
