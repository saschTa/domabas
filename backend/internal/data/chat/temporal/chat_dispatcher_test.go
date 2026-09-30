package temporal

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	w "github.com/domabas/domabas/backend/internal/domain/chat/workflows"
	"github.com/stretchr/testify/mock"
	common "go.temporal.io/api/common/v1"
	enums "go.temporal.io/api/enums/v1"
	historypb "go.temporal.io/api/history/v1"
	"go.temporal.io/api/serviceerror"
	taskqueue "go.temporal.io/api/taskqueue/v1"
	workflowpb "go.temporal.io/api/workflow/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/mocks"
)

type chatOutboxStub struct {
	dispatch func(context.Context) ([]m.ChatDispatch, error)
	ack      func(context.Context, m.ChatDispatch, string) error
	release  func(context.Context, m.ChatDispatch) error
	closed   func(context.Context, m.ChatDispatch, string) error
}

func (s *chatOutboxStub) Dispatch(ctx context.Context) ([]m.ChatDispatch, error) {
	if s.dispatch != nil {
		return s.dispatch(ctx)
	}
	return nil, nil
}
func (s *chatOutboxStub) Acknowledge(ctx context.Context, d m.ChatDispatch, id string) error {
	if s.ack != nil {
		return s.ack(ctx, d, id)
	}
	return nil
}
func (s *chatOutboxStub) ReleaseDelivery(ctx context.Context, d m.ChatDispatch) error {
	if s.release != nil {
		return s.release(ctx, d)
	}
	return nil
}
func (s *chatOutboxStub) Closed(ctx context.Context, d m.ChatDispatch, code string) error {
	if s.closed != nil {
		return s.closed(ctx, d, code)
	}
	return nil
}

func chatDispatchFixture() (m.ChatDispatch, *workflowservice.DescribeWorkflowExecutionResponse) {
	d := m.ChatDispatch{TurnID: "b25f9c51-87c5-48b1-8460-65ea11babc99", AccountID: "e9d6f5eb-151a-4889-b70d-ad7ce0f98e03", TaskQueue: "test-chat", DeliveryToken: "delivery-token", FirstStartAt: time.Now()}
	d.WorkflowID = ChatWorkflowID(d.TurnID)
	response := &workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: &workflowpb.WorkflowExecutionInfo{Execution: &common.WorkflowExecution{WorkflowId: d.WorkflowID, RunId: "test-run"}, Type: &common.WorkflowType{Name: w.ChatTurnWorkflowName}, TaskQueue: d.TaskQueue, Status: enums.WORKFLOW_EXECUTION_STATUS_RUNNING}}
	return d, response
}

func chatStartedEvent(t *testing.T, job m.ChatDispatch) *historypb.HistoryEvent {
	t.Helper()
	payloads, err := converter.GetDefaultDataConverter().ToPayloads(w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID})
	if err != nil {
		t.Fatal(err)
	}
	return &historypb.HistoryEvent{Attributes: &historypb.HistoryEvent_WorkflowExecutionStartedEventAttributes{WorkflowExecutionStartedEventAttributes: &historypb.WorkflowExecutionStartedEventAttributes{WorkflowType: &common.WorkflowType{Name: w.ChatTurnWorkflowName}, TaskQueue: &taskqueue.TaskQueue{Name: job.TaskQueue}, Input: payloads}}}
}

func expectChatHistory(t *testing.T, remote *mocks.Client, job m.ChatDispatch, event *historypb.HistoryEvent) {
	t.Helper()
	history := mocks.NewHistoryEventIterator(t)
	history.On("HasNext").Return(true).Once()
	history.On("Next").Return(event, nil).Once()
	remote.On("GetWorkflowHistory", mock.Anything, job.WorkflowID, "test-run", false, enums.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
}

func chatDispatcherFixture(service ChatOutboxService, remote ChatDispatchClient) *ChatDispatcher {
	return NewChatDispatcher(service, remote, "test-chat", slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func TestChatAmbiguousStartReconcilesWithoutSecondStart(t *testing.T) {
	job, response := chatDispatchFixture()
	remote := mocks.NewClient(t)
	remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "").Return(nil, serviceerror.NewNotFound("missing")).Once()
	remote.On("ExecuteWorkflow", mock.Anything, mock.MatchedBy(func(options client.StartWorkflowOptions) bool {
		return options.ID == job.WorkflowID && options.TaskQueue == job.TaskQueue && options.WorkflowExecutionTimeout == 24*time.Hour && options.WorkflowIDReusePolicy == enums.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE && options.WorkflowIDConflictPolicy == enums.WORKFLOW_ID_CONFLICT_POLICY_FAIL && options.WorkflowExecutionErrorWhenAlreadyStarted && options.Priority.PriorityKey == 5
	}), w.ChatTurnWorkflowName, w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID}).Return(nil, errors.New("response lost after start")).Once()
	remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "").Return(response, nil).Once()
	expectChatHistory(t, remote, job, chatStartedEvent(t, job))
	ack := false
	service := &chatOutboxStub{ack: func(_ context.Context, got m.ChatDispatch, runID string) error {
		ack = got.DeliveryToken == job.DeliveryToken && runID == "test-run"
		return nil
	}}
	d := chatDispatcherFixture(service, remote)
	if err := d.deliver(t.Context(), job); err == nil {
		t.Fatal("ambiguous start accepted")
	}
	if err := d.deliver(t.Context(), job); err != nil || !ack {
		t.Fatalf("reconciliation failed: %v", err)
	}
}

func TestChatAlreadyStartedAdoptsExactOwnedExecution(t *testing.T) {
	job, response := chatDispatchFixture()
	remote := mocks.NewClient(t)
	remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "").Return(nil, serviceerror.NewNotFound("missing")).Once()
	remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.ChatTurnWorkflowName, mock.Anything).Return(nil, &serviceerror.WorkflowExecutionAlreadyStarted{RunId: "test-run"}).Once()
	remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "test-run").Return(response, nil).Once()
	expectChatHistory(t, remote, job, chatStartedEvent(t, job))
	ack := false
	d := chatDispatcherFixture(&chatOutboxStub{ack: func(_ context.Context, got m.ChatDispatch, run string) error {
		ack = run == "test-run" && got.DeliveryToken == job.DeliveryToken
		return nil
	}}, remote)
	if err := d.deliver(t.Context(), job); err != nil || !ack {
		t.Fatalf("duplicate not adopted: %v", err)
	}
}

func TestChatRejectsForeignExecution(t *testing.T) {
	for _, mismatch := range []string{"queue", "type", "input", "extra input"} {
		t.Run(mismatch, func(t *testing.T) {
			job, response := chatDispatchFixture()
			remote := mocks.NewClient(t)
			if mismatch == "queue" {
				response.WorkflowExecutionInfo.TaskQueue = "foreign-schema"
			} else if mismatch == "type" {
				response.WorkflowExecutionInfo.Type.Name = "foreign-workflow"
			} else {
				event := chatStartedEvent(t, job)
				payload := event.GetWorkflowExecutionStartedEventAttributes().Input.Payloads[0]
				if mismatch == "input" {
					payload.Data = []byte(`{"turnId":"foreign","accountId":"foreign"}`)
				} else {
					payload.Data = append(payload.Data[:len(payload.Data)-1], []byte(`,"secret":"hidden"}`)...)
				}
				expectChatHistory(t, remote, job, event)
			}
			remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "").Return(response, nil).Once()
			d := chatDispatcherFixture(&chatOutboxStub{ack: func(context.Context, m.ChatDispatch, string) error { t.Fatal("foreign execution adopted"); return nil }}, remote)
			if err := d.deliver(t.Context(), job); err == nil {
				t.Fatal("foreign execution accepted")
			}
		})
	}
}

func TestChatCancellationUsesOwnedRunAndPreservesAdmission(t *testing.T) {
	job, response := chatDispatchFixture()
	job.CancelRequested = true
	job.RunID = "test-run"
	remote := mocks.NewClient(t)
	remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "test-run").Return(response, nil).Once()
	expectChatHistory(t, remote, job, chatStartedEvent(t, job))
	remote.On("CancelWorkflow", mock.Anything, job.WorkflowID, "test-run").Return(nil).Once()
	ack := false
	d := chatDispatcherFixture(&chatOutboxStub{ack: func(context.Context, m.ChatDispatch, string) error { ack = true; return nil }, closed: func(context.Context, m.ChatDispatch, string) error {
		t.Fatal("admission released before close")
		return nil
	}}, remote)
	if err := d.deliver(t.Context(), job); err != nil || !ack {
		t.Fatalf("cancel reconciliation failed: %v", err)
	}
}

func TestChatMissingHistoryNeverRestartsKnownExecution(t *testing.T) {
	for _, age := range []time.Duration{time.Hour, 21 * time.Hour, 25 * time.Hour} {
		t.Run(age.String(), func(t *testing.T) {
			job, _ := chatDispatchFixture()
			job.RunID = "test-run"
			job.FirstStartAt = time.Now().Add(-age)
			remote := mocks.NewClient(t)
			remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "test-run").Return(nil, serviceerror.NewNotFound("missing")).Once()
			var released bool
			var code string
			d := chatDispatcherFixture(&chatOutboxStub{release: func(context.Context, m.ChatDispatch) error { released = true; return nil }, closed: func(_ context.Context, _ m.ChatDispatch, value string) error { code = value; return nil }}, remote)
			if err := d.deliver(t.Context(), job); err != nil {
				t.Fatal(err)
			}
			if age < 24*time.Hour && (!released || code != "") {
				t.Fatal("missing history released execution ownership")
			}
			if age > 24*time.Hour && (released || code != "execution_lost") {
				t.Fatal("expired execution not fenced")
			}
		})
	}
}

func TestChatReconciliationRecordsSafeTerminalCode(t *testing.T) {
	for _, tc := range []struct {
		status enums.WorkflowExecutionStatus
		code   string
	}{{enums.WORKFLOW_EXECUTION_STATUS_COMPLETED, "chat_failed"}, {enums.WORKFLOW_EXECUTION_STATUS_CANCELED, "chat_cancelled"}, {enums.WORKFLOW_EXECUTION_STATUS_TIMED_OUT, "chat_timeout"}, {enums.WORKFLOW_EXECUTION_STATUS_FAILED, "chat_failed"}} {
		t.Run(tc.status.String(), func(t *testing.T) {
			job, response := chatDispatchFixture()
			response.WorkflowExecutionInfo.Status = tc.status
			remote := mocks.NewClient(t)
			remote.On("DescribeWorkflowExecution", mock.Anything, job.WorkflowID, "").Return(response, nil).Once()
			expectChatHistory(t, remote, job, chatStartedEvent(t, job))
			var code string
			d := chatDispatcherFixture(&chatOutboxStub{closed: func(_ context.Context, got m.ChatDispatch, value string) error {
				if got.RunID != "test-run" || got.DeliveryToken != job.DeliveryToken {
					t.Fatal("lost terminal ownership")
				}
				code = value
				return nil
			}}, remote)
			if err := d.deliver(t.Context(), job); err != nil || code != tc.code {
				t.Fatalf("code=%q err=%v", code, err)
			}
		})
	}
}

func TestChatDispatcherReadinessRequiresSuccessfulTickAndCloseDrains(t *testing.T) {
	started := make(chan struct{})
	drained := make(chan struct{})
	remote := mocks.NewClient(t)
	var calls atomic.Int32
	d := chatDispatcherFixture(&chatOutboxStub{dispatch: func(ctx context.Context) ([]m.ChatDispatch, error) {
		if calls.Add(1) == 1 {
			return nil, nil
		}
		close(started)
		<-ctx.Done()
		close(drained)
		return nil, ctx.Err()
	}}, remote)
	if err := d.Start(); err != nil {
		t.Fatal(err)
	}
	<-started
	if err := d.Ping(); err != nil {
		t.Fatal("not ready after successful initial dispatch")
	}
	d.tick.Store(time.Now().Add(-time.Minute).UnixNano())
	if err := d.Ping(); err == nil {
		t.Fatal("stale dispatcher remained ready")
	}
	d.Close()
	select {
	case <-drained:
	default:
		t.Fatal("close did not join dispatcher")
	}
	if err := d.Ping(); err == nil {
		t.Fatal("closed dispatcher ready")
	}
	if err := d.Start(); err == nil {
		t.Fatal("closed dispatcher restarted")
	}
}

func TestChatDispatcherStartFailsWithoutSuccessfulProbe(t *testing.T) {
	d := chatDispatcherFixture(&chatOutboxStub{dispatch: func(context.Context) ([]m.ChatDispatch, error) { return nil, errors.New("database unavailable") }}, mocks.NewClient(t))
	if err := d.Start(t.Context()); err == nil {
		t.Fatal("failed initial dispatch was accepted")
	}
	if err := d.Ping(); err == nil {
		t.Fatal("unstarted dispatcher was ready")
	}
	d.Close()
}

func TestChatDispatcherRetentionFailureDoesNotClaim(t *testing.T) {
	remote := mocks.NewClient(t)
	d := chatDispatcherFixture(&chatOutboxStub{dispatch: func(context.Context) ([]m.ChatDispatch, error) {
		t.Fatal("claimed without sufficient retention")
		return nil, nil
	}}, remote)
	d.retention = func(context.Context) error { return errors.New("insufficient retention") }
	if err := d.dispatch(t.Context()); err == nil {
		t.Fatal("retention error ignored")
	}
}
