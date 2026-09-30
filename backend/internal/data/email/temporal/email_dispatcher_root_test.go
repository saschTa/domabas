package temporal

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"
	"github.com/stretchr/testify/mock"
	commonpb "go.temporal.io/api/common/v1"
	enumspb "go.temporal.io/api/enums/v1"
	historypb "go.temporal.io/api/history/v1"
	"go.temporal.io/api/serviceerror"
	workflowpb "go.temporal.io/api/workflow/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/mocks"
)

type rootDispatchService struct {
	acknowledge func(context.Context, m.EmailExecution, string) error
	pending     []m.EmailExecution
	resolve     func(context.Context, m.EmailExecution, string, string, bool) error
}

func (*rootDispatchService) Schedule(context.Context) error { return nil }

func (*rootDispatchService) ClaimDelivery(context.Context, string) (*m.EmailExecution, error) {
	return nil, nil
}

func (s *rootDispatchService) AcknowledgeDelivery(ctx context.Context, execution m.EmailExecution, run string) error {
	return s.acknowledge(ctx, execution, run)
}

func (s *rootDispatchService) PendingExecutions(context.Context) ([]m.EmailExecution, error) {
	return s.pending, nil
}

func (s *rootDispatchService) ResolveExecution(ctx context.Context, execution m.EmailExecution, run, code string, missing bool) error {
	return s.resolve(ctx, execution, run, code, missing)
}

func (*rootDispatchService) Cleanup(context.Context) error { return nil }

func (*rootDispatchService) Rotate(context.Context) error { return nil }

func rootExecutionFixture() (m.EmailExecution, *workflowservice.DescribeWorkflowExecutionResponse) {
	id := "b25f9c51-87c5-48b1-8460-65ea11babc99"
	execution := m.EmailExecution{RunID: id, WorkflowID: "domabas-email-" + id, TaskQueue: "disposable-email-queue", LeaseToken: "lease", FirstAttemptAt: time.Now(), LatestPermitEnd: time.Now().Add(5 * time.Second), StartWindowEnd: time.Now().Add(time.Hour)}
	response := &workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: &workflowpb.WorkflowExecutionInfo{Execution: &commonpb.WorkflowExecution{WorkflowId: execution.WorkflowID, RunId: "owned-run"}, Type: &commonpb.WorkflowType{Name: emailworkflows.EmailPollWorkflowName}, TaskQueue: execution.TaskQueue, Status: enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING}}
	return execution, response
}

func rootStartHistory(t *testing.T, remote *mocks.Client, execution m.EmailExecution, input emailworkflows.EmailPollWorkflowInput) {
	t.Helper()
	payloads, err := converter.GetDefaultDataConverter().ToPayloads(input)
	if err != nil {
		t.Fatal(err)
	}
	history := mocks.NewHistoryEventIterator(t)
	history.On("HasNext").Return(true).Once()
	history.On("Next").Return(&historypb.HistoryEvent{Attributes: &historypb.HistoryEvent_WorkflowExecutionStartedEventAttributes{WorkflowExecutionStartedEventAttributes: &historypb.WorkflowExecutionStartedEventAttributes{Input: payloads}}}, nil).Once()
	remote.On("GetWorkflowHistory", mock.Anything, execution.WorkflowID, "owned-run", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
}

func rootDispatcher(service *rootDispatchService, remote EmailTemporalClient) *EmailPollDispatcher {
	return NewEmailPollDispatcher(service, service, remote, "disposable-email-queue", slog.New(slog.NewTextHandler(io.Discard, nil)), func(context.Context) error { return nil })
}

func TestEmailDeliveryRecoversLostAcknowledgementWithoutReplacingExecution(t *testing.T) {
	execution, response := rootExecutionFixture()
	acknowledged := 0
	service := &rootDispatchService{acknowledge: func(_ context.Context, got m.EmailExecution, run string) error {
		if got.RunID != execution.RunID || got.LeaseToken != execution.LeaseToken || run != "owned-run" {
			t.Fatal("acknowledged the wrong delivery or workflow execution")
		}
		acknowledged++
		if acknowledged == 1 {
			return errors.New("database acknowledgement unavailable")
		}
		return nil
	}}
	remote := mocks.NewClient(t)
	run := mocks.NewWorkflowRun(t)
	run.On("GetID").Return(execution.WorkflowID)
	run.On("GetRunID").Return("owned-run")
	options := mock.MatchedBy(func(value client.StartWorkflowOptions) bool {
		return value.ID == execution.WorkflowID && value.TaskQueue == execution.TaskQueue && value.WorkflowExecutionTimeout == 10*time.Minute && value.WorkflowExecutionErrorWhenAlreadyStarted && value.WorkflowIDReusePolicy == enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE && value.WorkflowIDConflictPolicy == enumspb.WORKFLOW_ID_CONFLICT_POLICY_FAIL && value.RetryPolicy == nil
	})
	bounded := mock.MatchedBy(func(ctx context.Context) bool {
		deadline, ok := ctx.Deadline()
		return ok && !deadline.After(execution.LatestPermitEnd)
	})
	remote.On("ExecuteWorkflow", bounded, options, emailworkflows.EmailPollWorkflowName, emailworkflows.EmailPollWorkflowInput{RunID: execution.RunID}).Return(run, nil).Once()
	remote.On("ExecuteWorkflow", bounded, options, emailworkflows.EmailPollWorkflowName, emailworkflows.EmailPollWorkflowInput{RunID: execution.RunID}).Return(nil, &serviceerror.WorkflowExecutionAlreadyStarted{RunId: "owned-run"}).Once()
	remote.On("DescribeWorkflowExecution", mock.Anything, execution.WorkflowID, "owned-run").Return(response, nil).Once()
	rootStartHistory(t, remote, execution, emailworkflows.EmailPollWorkflowInput{RunID: execution.RunID})
	dispatcher := rootDispatcher(service, remote)
	if err := dispatcher.deliver(t.Context(), execution); err == nil {
		t.Fatal("lost acknowledgement was reported as durable")
	}
	if err := dispatcher.deliver(t.Context(), execution); err != nil || acknowledged != 2 {
		t.Fatalf("duplicate delivery failed to recover: acknowledgements=%d err=%v", acknowledged, err)
	}
}

func TestEmailDeliveryDoesNotStartKnownExpiredOrForeignIdentity(t *testing.T) {
	for _, name := range []string{"known_run", "expired_permit", "expired_start_window", "foreign_workflow", "missing_queue"} {
		t.Run(name, func(t *testing.T) {
			execution, _ := rootExecutionFixture()
			switch name {
			case "known_run":
				execution.WorkflowRunID = "owned-run"
			case "expired_permit":
				execution.LatestPermitEnd = time.Now().Add(-time.Second)
			case "expired_start_window":
				execution.StartWindowEnd = time.Now().Add(-time.Second)
			case "foreign_workflow":
				execution.WorkflowID = "another-workflow"
			case "missing_queue":
				execution.TaskQueue = ""
			}
			if err := rootDispatcher(&rootDispatchService{}, mocks.NewClient(t)).deliver(t.Context(), execution); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestEmailReconciliationKeepsExactKnownRunAfterHistoryDisappears(t *testing.T) {
	execution, _ := rootExecutionFixture()
	execution.WorkflowRunID = "owned-run"
	resolved := false
	service := &rootDispatchService{pending: []m.EmailExecution{execution}, resolve: func(_ context.Context, got m.EmailExecution, run, code string, missing bool) error {
		resolved = true
		if got.RunID != execution.RunID || run != "owned-run" || code != "delivery_timeout" || !missing {
			t.Fatal("missing history lost exact ownership or absence classification")
		}
		return nil
	}}
	remote := mocks.NewClient(t)
	remote.On("DescribeWorkflowExecution", mock.Anything, execution.WorkflowID, "owned-run").Return(nil, serviceerror.NewNotFound("history expired")).Once()
	if err := rootDispatcher(service, remote).reconcile(t.Context()); err != nil || !resolved {
		t.Fatalf("known run reconciliation failed: resolved=%v err=%v", resolved, err)
	}
}

func TestEmailKnownRunReconciliationUsesDescribeWithoutHistoryOrRestart(t *testing.T) {
	for _, scenario := range []struct {
		name   string
		status enumspb.WorkflowExecutionStatus
		closed bool
		code   string
	}{
		{name: "running", status: enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING},
		{name: "completed", status: enumspb.WORKFLOW_EXECUTION_STATUS_COMPLETED, closed: true},
		{name: "failed", status: enumspb.WORKFLOW_EXECUTION_STATUS_FAILED, closed: true, code: "processing_failed"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			execution, response := rootExecutionFixture()
			execution.WorkflowRunID = "owned-run"
			response.WorkflowExecutionInfo.Status = scenario.status
			resolved := false
			service := &rootDispatchService{pending: []m.EmailExecution{execution}, resolve: func(_ context.Context, got m.EmailExecution, run, code string, missing bool) error {
				resolved = true
				if got.RunID != execution.RunID || run != "owned-run" || code != scenario.code || missing {
					t.Fatal("known execution outcome changed ownership or classification")
				}
				return nil
			}}
			remote := mocks.NewClient(t)
			remote.On("DescribeWorkflowExecution", mock.Anything, execution.WorkflowID, "owned-run").Return(response, nil).Once()
			if err := rootDispatcher(service, remote).reconcile(t.Context()); err != nil || resolved != scenario.closed {
				t.Fatalf("known run reconciliation: resolved=%v err=%v", resolved, err)
			}
		})
	}
}

func TestEmailExecutionVerificationRejectsForeignTypeQueueRunAndInput(t *testing.T) {
	for _, name := range []string{"type", "queue", "run", "input"} {
		t.Run(name, func(t *testing.T) {
			execution, response := rootExecutionFixture()
			input := emailworkflows.EmailPollWorkflowInput{RunID: execution.RunID}
			switch name {
			case "type":
				response.WorkflowExecutionInfo.Type.Name = "other-type"
			case "queue":
				response.WorkflowExecutionInfo.TaskQueue = "other-queue"
			case "run":
				response.WorkflowExecutionInfo.Execution.RunId = "other-run"
			case "input":
				input.RunID = "another-email-run"
			}
			remote := mocks.NewClient(t)
			remote.On("DescribeWorkflowExecution", mock.Anything, execution.WorkflowID, "owned-run").Return(response, nil).Once()
			if name == "input" {
				rootStartHistory(t, remote, execution, input)
			}
			if _, err := verifyExecution(t.Context(), remote, execution.RunID, "owned-run", execution.TaskQueue); err == nil {
				t.Fatal("adopted an unrelated execution")
			}
		})
	}
}

func TestEmailDispatcherCloseCancelsAndDrainsMaintenance(t *testing.T) {
	entered := make(chan struct{})
	exited := make(chan struct{})
	service := &rootDispatchService{}
	dispatcher := rootDispatcher(service, mocks.NewClient(t))
	dispatcher.retention = func(ctx context.Context) error {
		close(entered)
		<-ctx.Done()
		close(exited)
		return ctx.Err()
	}
	if err := dispatcher.Start(); err != nil {
		t.Fatal(err)
	}
	defer dispatcher.Close()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("dispatcher did not enter its owned operation")
	}
	dispatcher.Close()
	select {
	case <-exited:
	default:
		t.Fatal("dispatcher close returned before the operation drained")
	}
	if dispatcher.Ping() == nil || dispatcher.Start() == nil {
		t.Fatal("stopped dispatcher reported readiness or restarted")
	}
}
