package temporal_test

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/llm"
	adapter "github.com/domabas/domabas/backend/internal/data/document/temporal"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	workflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/temporal"
)

type aiScheduledServices struct {
	work         func(context.Context, document.DocumentJob) error
	backlog      atomic.Bool
	backlogReads atomic.Int32
}

func (s *aiScheduledServices) IngestionPending(context.Context) (bool, error) {
	s.backlogReads.Add(1)
	return s.backlog.Load(), nil
}
func (s *aiScheduledServices) Enrich(ctx context.Context, job document.DocumentJob) error {
	return s.work(ctx, job)
}
func (s *aiScheduledServices) ExtractInvoice(ctx context.Context, job document.DocumentJob) error {
	return s.work(ctx, job)
}
func (s *aiScheduledServices) Complete(context.Context, document.DocumentJob) error     { return nil }
func (s *aiScheduledServices) Fail(context.Context, document.DocumentJob, string) error { return nil }

func aiScheduledRequest() workflows.DocumentIngestionRequest {
	return workflows.DocumentIngestionRequest{
		AccountID: accountID, DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99",
		Generation: 1, AIAttempt: 1, UnlimitedInference: true,
	}
}

func TestAIAdmittedHTTPFinishesWhenIngestionArrives(t *testing.T) {
	for _, stage := range []string{"properties", "invoice"} {
		t.Run(stage, func(t *testing.T) {
			t.Parallel()
			var requests atomic.Int32
			started, finish := make(chan struct{}), make(chan struct{})
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, _ = io.Copy(io.Discard, r.Body)
				if r.URL.Path == "/api/show" {
					_, _ = io.WriteString(w, `{"model_info":{"general.architecture":"qwen35","qwen35.context_length":131072}}`)
					return
				}
				if r.URL.Path != "/api/chat" {
					w.WriteHeader(http.StatusNotFound)
					return
				}
				if requests.Add(1) == 1 {
					close(started)
				}
				select {
				case <-r.Context().Done():
					t.Error("ingestion cancelled the admitted HTTP request")
				case <-ctx.Done():
				case <-finish:
					_, _ = io.WriteString(w, `{"message":{"content":"{}"},"done":true,"done_reason":"stop"}`)
				}
			}))
			defer server.Close()
			remote, err := llm.NewDocumentPropertyRemoteDataSource(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			defer remote.Close()
			service := &aiScheduledServices{work: func(ctx context.Context, job document.DocumentJob) error {
				if job.AIAttempt != 1 {
					t.Errorf("changed durable attempt: %+v", job)
				}
				_, err := remote.Generate(ctx, "ollama", "fixture-model", "", "", "extract", `{}`, "document text", 64, 0, false, false)
				return err
			}}
			activities := adapter.NewDocumentAIActivities(service, service, service)
			defer activities.Close()
			result := make(chan error, 1)
			go func() {
				if stage == "invoice" {
					result <- activities.Invoice(ctx, aiScheduledRequest())
				} else {
					result <- activities.Enrich(ctx, aiScheduledRequest())
				}
			}()
			select {
			case <-started:
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			service.backlog.Store(true)
			select {
			case err := <-result:
				t.Fatalf("admitted provider stopped when ingestion arrived: %v", err)
			case <-time.After(1100 * time.Millisecond):
			}
			close(finish)
			if err := <-result; err != nil {
				t.Fatal(err)
			}
			if requests.Load() != 1 || service.backlogReads.Load() != 0 {
				t.Fatalf("provider requests=%d backlog reads=%d", requests.Load(), service.backlogReads.Load())
			}
		})
	}
}

func TestAIAdmittedActivityPreservesProviderOutcome(t *testing.T) {
	for _, outcome := range []struct {
		name string
		err  error
		code string
	}{
		{name: "success"},
		{name: "provider failure", err: document.DocumentProcessingError{Code: "invalid_invoice"}, code: "invalid_invoice"},
	} {
		t.Run(outcome.name, func(t *testing.T) {
			calls := 0
			service := &aiScheduledServices{work: func(context.Context, document.DocumentJob) error { calls++; return outcome.err }}
			service.backlog.Store(true)
			activities := adapter.NewDocumentAIActivities(service, service, service)
			defer activities.Close()
			err := activities.Invoice(t.Context(), aiScheduledRequest())
			if outcome.code == "" && err != nil {
				t.Fatal(err)
			}
			if outcome.code != "" {
				var failure *temporal.ApplicationError
				if !errors.As(err, &failure) || failure.Type() != outcome.code {
					t.Fatalf("provider failure was masked: %v", err)
				}
			}
			if calls != 1 || service.backlogReads.Load() != 0 {
				t.Fatal(calls, service.backlogReads.Load())
			}
		})
	}
}

func TestAIAdmittedActivityCancellationDrainsProvider(t *testing.T) {
	for _, mode := range []string{"parent cancellation", "worker shutdown"} {
		t.Run(mode, func(t *testing.T) {
			t.Parallel()
			started := make(chan struct{})
			var active atomic.Bool
			service := &aiScheduledServices{work: func(ctx context.Context, _ document.DocumentJob) error {
				active.Store(true)
				close(started)
				<-ctx.Done()
				active.Store(false)
				return ctx.Err()
			}}
			activities := adapter.NewDocumentAIActivities(service, service, service)
			defer activities.Close()
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			result := make(chan error, 1)
			go func() { result <- activities.Invoice(ctx, aiScheduledRequest()) }()
			<-started
			if mode == "parent cancellation" {
				cancel()
			} else {
				activities.Close()
			}
			select {
			case err := <-result:
				if err == nil || active.Load() {
					t.Fatal("interrupted activity did not drain provider", err, active.Load())
				}
				if mode == "parent cancellation" && !temporal.IsCanceledError(err) {
					t.Fatal(err)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("activity ignored cancellation")
			}
		})
	}
}
