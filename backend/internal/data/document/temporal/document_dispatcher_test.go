package temporal

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/stretchr/testify/mock"
	commonpb "go.temporal.io/api/common/v1"
	enumspb "go.temporal.io/api/enums/v1"
	historypb "go.temporal.io/api/history/v1"
	"go.temporal.io/api/serviceerror"
	taskqueuepb "go.temporal.io/api/taskqueue/v1"
	workflowpb "go.temporal.io/api/workflow/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/mocks"
)

type outboxStub struct {
	claim       func(context.Context, int, time.Duration) ([]document.DocumentOutboxLease, error)
	acknowledge func(context.Context, document.DocumentOutboxLease, string, string) error
	release     func(context.Context, document.DocumentOutboxLease, time.Time) error
	pending     func(context.Context, int) ([]document.DocumentPendingJob, error)
	fail        func(context.Context, document.DocumentJob, string) error
}

func (service *outboxStub) Claim(ctx context.Context, limit int, lease time.Duration, _ ...string) ([]document.DocumentOutboxLease, error) {
	return service.claim(ctx, limit, lease)
}

func (service *outboxStub) Acknowledge(ctx context.Context, lease document.DocumentOutboxLease, workflowID, runID string) error {
	return service.acknowledge(ctx, lease, workflowID, runID)
}

func (service *outboxStub) Release(ctx context.Context, lease document.DocumentOutboxLease, retryAt time.Time) error {
	return service.release(ctx, lease, retryAt)
}

func (service *outboxStub) Pending(ctx context.Context, limit int) ([]document.DocumentPendingJob, error) {
	return service.pending(ctx, limit)
}

func (service *outboxStub) FailExpired(ctx context.Context, job document.DocumentJob, code string) error {
	return service.fail(ctx, job, code)
}

func (service *outboxStub) Fail(ctx context.Context, job document.DocumentJob, code string) error {
	return service.fail(ctx, job, code)
}

func (service *outboxStub) ReapUploads(context.Context) error { return nil }

func deliveryFixture() (document.DocumentOutboxLease, *workflowservice.DescribeWorkflowExecutionResponse) {
	job := document.DocumentJob{AccountID: "e9d6f5eb-151a-4889-b70d-ad7ce0f98e03", DocumentID: "b25f9c51-87c5-48b1-8460-65ea11babc99", Generation: 3}
	lease := document.DocumentOutboxLease{WorkflowID: IngestionWorkflowID(job), TaskQueue: "test-queue", PermitEnd: time.Now().Add(5 * time.Second), ID: "outbox-id", LeaseToken: "lease-token", Job: job, DeliveryDeadline: time.Now().Add(time.Hour)}
	response := &workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: &workflowpb.WorkflowExecutionInfo{
		Execution: &commonpb.WorkflowExecution{WorkflowId: IngestionWorkflowID(job), RunId: "test-run"},
		Type:      &commonpb.WorkflowType{Name: documentworkflows.DocumentIngestionWorkflowName}, TaskQueue: "test-queue", Status: enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING,
	}}
	return lease, response
}

func startEvent(t *testing.T, input documentworkflows.DocumentIngestionRequest) *historypb.HistoryEvent {
	t.Helper()
	payloads, err := converter.GetDefaultDataConverter().ToPayloads(input)
	if err != nil {
		t.Fatal(err)
	}
	return &historypb.HistoryEvent{Attributes: &historypb.HistoryEvent_WorkflowExecutionStartedEventAttributes{
		WorkflowExecutionStartedEventAttributes: &historypb.WorkflowExecutionStartedEventAttributes{
			WorkflowType: &commonpb.WorkflowType{Name: documentworkflows.DocumentIngestionWorkflowName}, TaskQueue: &taskqueuepb.TaskQueue{Name: "test-queue"}, Input: payloads,
		},
	}}
}

func TestDeliveryResumesAfterStartBeforeAcknowledgement(t *testing.T) {
	lease, response := deliveryFixture()
	var acknowledgements int
	service := &outboxStub{acknowledge: func(_ context.Context, got document.DocumentOutboxLease, workflowID, runID string) error {
		if got.LeaseToken != lease.LeaseToken || workflowID != IngestionWorkflowID(lease.Job) || runID != "test-run" {
			t.Fatal("acknowledgement lost lease or exact execution identity")
		}
		acknowledgements++
		if acknowledgements == 1 {
			return errors.New("database disconnected after workflow start")
		}
		return nil
	}}
	remote := mocks.NewClient(t)
	run := mocks.NewWorkflowRun(t)
	run.On("GetID").Return(IngestionWorkflowID(lease.Job))
	run.On("GetRunID").Return("test-run")
	options := mock.MatchedBy(func(value client.StartWorkflowOptions) bool {
		return value.ID == IngestionWorkflowID(lease.Job) && value.TaskQueue == "test-queue" && value.WorkflowExecutionTimeout == 15*time.Minute && value.WorkflowExecutionErrorWhenAlreadyStarted && value.WorkflowIDReusePolicy == enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE && value.WorkflowIDConflictPolicy == enumspb.WORKFLOW_ID_CONFLICT_POLICY_FAIL && value.RetryPolicy == nil
	})
	remote.On("ExecuteWorkflow", mock.Anything, options, documentworkflows.DocumentIngestionWorkflowName, ingestionRequest(lease.Job)).Return(run, nil).Once()
	remote.On("ExecuteWorkflow", mock.Anything, options, documentworkflows.DocumentIngestionWorkflowName, ingestionRequest(lease.Job)).Return(nil, &serviceerror.WorkflowExecutionAlreadyStarted{RunId: "test-run"}).Once()
	remote.On("DescribeWorkflowExecution", mock.Anything, IngestionWorkflowID(lease.Job), "test-run").Return(response, nil).Once()
	history := mocks.NewHistoryEventIterator(t)
	history.On("HasNext").Return(true).Once()
	history.On("Next").Return(startEvent(t, ingestionRequest(lease.Job)), nil).Once()
	remote.On("GetWorkflowHistory", mock.Anything, IngestionWorkflowID(lease.Job), "test-run", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
	dispatcher := NewDocumentIngestionDispatcher(service, remote, "test-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := dispatcher.deliver(t.Context(), lease); err == nil {
		t.Fatal("lost acknowledgement was silently accepted")
	}
	if err := dispatcher.deliver(t.Context(), lease); err != nil || acknowledgements != 2 {
		t.Fatalf("duplicate delivery did not recover exact existing execution: %v", err)
	}
}

func TestDuplicateDeliveryDoesNotAdoptForeignExecution(t *testing.T) {
	for _, mismatch := range []string{"type", "queue", "input", "extra input", "execution mode"} {
		t.Run(mismatch, func(t *testing.T) {
			lease, response := deliveryFixture()
			var released bool
			service := &outboxStub{acknowledge: func(context.Context, document.DocumentOutboxLease, string, string) error {
				t.Fatal("acknowledged an unrelated execution")
				return nil
			}, release: func(_ context.Context, got document.DocumentOutboxLease, retryAt time.Time) error {
				if got.LeaseToken != lease.LeaseToken || !retryAt.After(time.Now()) {
					t.Fatal("released wrong lease without bounded retry")
				}
				released = true
				return nil
			}}
			remote := mocks.NewClient(t)
			remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, documentworkflows.DocumentIngestionWorkflowName, ingestionRequest(lease.Job)).Return(nil, &serviceerror.WorkflowExecutionAlreadyStarted{RunId: "test-run"}).Once()
			if mismatch == "type" {
				response.WorkflowExecutionInfo.Type.Name = "unrelated-workflow"
			} else if mismatch == "queue" {
				response.WorkflowExecutionInfo.TaskQueue = "unrelated-database"
			} else {
				input := ingestionRequest(lease.Job)
				if mismatch == "input" {
					input.Generation++
				}
				if mismatch == "execution mode" {
					input.UnlimitedInference = true
				}
				event := startEvent(t, input)
				if mismatch == "extra input" {
					payload := event.GetWorkflowExecutionStartedEventAttributes().Input.Payloads[0]
					payload.Data = append(payload.Data[:len(payload.Data)-1], []byte(`,"privateText":"unexpected"}`)...)
				}
				history := mocks.NewHistoryEventIterator(t)
				history.On("HasNext").Return(true).Once()
				history.On("Next").Return(event, nil).Once()
				remote.On("GetWorkflowHistory", mock.Anything, IngestionWorkflowID(lease.Job), "test-run", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
			}
			remote.On("DescribeWorkflowExecution", mock.Anything, IngestionWorkflowID(lease.Job), "test-run").Return(response, nil).Once()
			dispatcher := NewDocumentIngestionDispatcher(service, remote, "test-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
			if err := dispatcher.deliver(t.Context(), lease); err == nil || !released {
				t.Fatalf("mismatched duplicate execution accepted: %v", err)
			}
		})
	}
}

func TestReconciliationHandlesTerminalRunsAndMissingHistoryDeadline(t *testing.T) {
	for _, scenario := range []struct {
		name   string
		status enumspb.WorkflowExecutionStatus
		code   string
	}{
		{"running", enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING, ""},
		{"completed without publication", enumspb.WORKFLOW_EXECUTION_STATUS_COMPLETED, "processing_incomplete"},
		{"failed", enumspb.WORKFLOW_EXECUTION_STATUS_FAILED, "processing_failed"},
		{"cancelled", enumspb.WORKFLOW_EXECUTION_STATUS_CANCELED, "processing_cancelled"},
		{"terminated", enumspb.WORKFLOW_EXECUTION_STATUS_TERMINATED, "processing_terminated"},
		{"timed out", enumspb.WORKFLOW_EXECUTION_STATUS_TIMED_OUT, "processing_timeout"},
		{"missing history", enumspb.WORKFLOW_EXECUTION_STATUS_UNSPECIFIED, ""},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			lease, response := deliveryFixture()
			deadline := time.Now().Add(time.Minute)
			pending := document.DocumentPendingJob{TaskQueue: "test-queue", LatestPermitEnd: &lease.PermitEnd, Job: lease.Job, WorkflowID: IngestionWorkflowID(lease.Job), RunID: "test-run", State: "processing", DeliveryDeadline: lease.DeliveryDeadline, ProcessingDeadline: &deadline}
			var code string
			service := &outboxStub{fail: func(_ context.Context, job document.DocumentJob, value string) error {
				if job != lease.Job {
					t.Fatal("reconciliation changed generation scope")
				}
				code = value
				return nil
			}}
			remote := mocks.NewClient(t)
			if scenario.name == "missing history" {
				remote.On("DescribeWorkflowExecution", mock.Anything, pending.WorkflowID, pending.RunID).Return(nil, serviceerror.NewNotFound("retention expired")).Once()
			} else {
				response.WorkflowExecutionInfo.Status = scenario.status
				remote.On("DescribeWorkflowExecution", mock.Anything, pending.WorkflowID, pending.RunID).Return(response, nil).Once()
			}
			dispatcher := NewDocumentIngestionDispatcher(service, remote, "test-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
			if err := dispatcher.reconcileJob(t.Context(), pending); err != nil || code != scenario.code {
				t.Fatalf("reconciliation: code %q, error %v", code, err)
			}
			if scenario.name == "missing history" {
				remote.On("DescribeWorkflowExecution", mock.Anything, pending.WorkflowID, pending.RunID).Return(nil, serviceerror.NewNotFound("retention expired")).Once()
				old := time.Now().Add(-16 * time.Minute)
				pending.LatestPermitEnd = &old
				dispatcher.now = func() time.Time { return deadline.Add(time.Second) }
				if err := dispatcher.reconcileJob(t.Context(), pending); err != nil || code != "processing_timeout" {
					t.Fatalf("expired missing history did not fence the generation: %q %v", code, err)
				}
			}
		})
	}
}

func TestLegacyKnownRunVerifiesInputBeforeAdoptingUnknownQueue(t *testing.T) {
	for _, mismatch := range []bool{false, true} {
		t.Run(fmt.Sprintf("mismatched input=%t", mismatch), func(t *testing.T) {
			lease, response := deliveryFixture()
			response.WorkflowExecutionInfo.Status = enumspb.WORKFLOW_EXECUTION_STATUS_COMPLETED
			pending := document.DocumentPendingJob{Job: lease.Job, WorkflowID: lease.WorkflowID, RunID: "test-run", Legacy: true}
			resolved := false
			service := &outboxStub{fail: func(context.Context, document.DocumentJob, string) error {
				resolved = true
				return nil
			}}
			input := ingestionRequest(lease.Job)
			if mismatch {
				input.Generation++
			}
			history := mocks.NewHistoryEventIterator(t)
			history.On("HasNext").Return(true).Once()
			history.On("Next").Return(startEvent(t, input), nil).Once()
			remote := mocks.NewClient(t)
			remote.On("DescribeWorkflowExecution", mock.Anything, lease.WorkflowID, pending.RunID).Return(response, nil).Once()
			remote.On("GetWorkflowHistory", mock.Anything, lease.WorkflowID, pending.RunID, false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
			dispatcher := NewDocumentIngestionDispatcher(service, remote, "replacement-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
			err := dispatcher.reconcileJob(t.Context(), pending)
			if mismatch && (err == nil || resolved) {
				t.Fatalf("adopted an unrelated legacy execution: %v", err)
			}
			if !mismatch && (err != nil || !resolved) {
				t.Fatalf("did not drain the verified legacy queue: %v", err)
			}
		})
	}
}

func TestDispatcherCloseCancelsAndDrainsBothLoops(t *testing.T) {
	entered := make(chan struct{}, 2)
	var released atomic.Int32
	service := &outboxStub{
		claim: func(ctx context.Context, limit int, lease time.Duration) ([]document.DocumentOutboxLease, error) {
			if limit > 20 || lease != 30*time.Second {
				t.Error("unbounded delivery claim")
			}
			entered <- struct{}{}
			<-ctx.Done()
			released.Add(1)
			return nil, ctx.Err()
		},
		pending: func(ctx context.Context, limit int) ([]document.DocumentPendingJob, error) {
			if limit > 100 {
				t.Error("unbounded reconciliation claim")
			}
			entered <- struct{}{}
			<-ctx.Done()
			released.Add(1)
			return nil, ctx.Err()
		},
	}
	dispatcher := NewDocumentIngestionDispatcher(service, mocks.NewClient(t), "test-queue", slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := dispatcher.Ping(); err == nil {
		t.Fatal("unstarted dispatcher is ready")
	}
	if err := dispatcher.Start(); err != nil {
		t.Fatal(err)
	}
	<-entered
	<-entered
	if err := dispatcher.Ping(); err != nil {
		t.Fatal(err)
	}
	dispatcher.Close()
	if released.Load() != 2 {
		t.Fatal("closed dispatcher retained in-flight database work")
	}
	if err := dispatcher.Ping(); err == nil {
		t.Fatal("closed dispatcher remained ready")
	}
	if err := dispatcher.Start(); err == nil {
		t.Fatal("closed dispatcher restarted")
	}
}

func (service *outboxStub) ResolveExecution(ctx context.Context, p document.DocumentPendingJob, run, code string, missing bool) error {
	if missing && p.LatestPermitEnd != nil && time.Now().Before(p.LatestPermitEnd.Add(15*time.Minute)) {
		return nil
	}
	if code == "" {
		return nil
	}
	return service.fail(ctx, p.Job, code)
}
