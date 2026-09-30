package temporal

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	w "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/stretchr/testify/mock"
	commonpb "go.temporal.io/api/common/v1"
	enumspb "go.temporal.io/api/enums/v1"
	historypb "go.temporal.io/api/history/v1"
	"go.temporal.io/api/serviceerror"
	taskqueuepb "go.temporal.io/api/taskqueue/v1"
	workflowpb "go.temporal.io/api/workflow/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/mocks"
	"go.temporal.io/sdk/testsuite"
	"io"
	"log/slog"
	"testing"
	"time"
)

type thumbnailActivityStub struct {
	attempts, failures int
	terminal           bool
	outcome            m.DocumentThumbnailOutcome
	finished           bool
}

func (s *thumbnailActivityStub) Render(context.Context, m.DocumentThumbnailJob) error {
	s.attempts++
	if s.terminal {
		return m.DocumentProcessingError{Code: "invalid_file"}
	}
	if s.attempts <= s.failures {
		return m.ErrUnavailable
	}
	return nil
}
func (s *thumbnailActivityStub) Finish(_ context.Context, _ m.DocumentThumbnailJob, o m.DocumentThumbnailOutcome) error {
	s.finished = true
	s.outcome = o
	return nil
}
func TestThumbnailWorkflowRetryOutcomes(t *testing.T) {
	for _, scenario := range []struct {
		name                               string
		failures                           int
		terminal                           bool
		attempts                           int
		finished, retryable, workflowError bool
	}{
		{name: "success", attempts: 1}, {name: "transient recovery", failures: 2, attempts: 3}, {name: "durable cooldown after exhaustion", failures: 9, attempts: 3, finished: true, retryable: true, workflowError: true}, {name: "terminal malformed source", terminal: true, attempts: 1, finished: true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			stub := &thumbnailActivityStub{failures: scenario.failures, terminal: scenario.terminal}
			activities := NewDocumentThumbnailActivities(stub)
			defer activities.Close()
			var suite testsuite.WorkflowTestSuite
			env := suite.NewTestWorkflowEnvironment()
			env.RegisterActivityWithOptions(activities.Render, activity.RegisterOptions{Name: w.RenderDocumentThumbnailActivity})
			env.RegisterActivityWithOptions(activities.Finish, activity.RegisterOptions{Name: w.FinishDocumentThumbnailActivity})
			env.ExecuteWorkflow(w.DocumentThumbnailWorkflow, w.DocumentThumbnailRequest{JobID: "job", AccountID: "account", DocumentID: "document", SourceSHA256: "source", RendererRevision: 1, Attempt: 1})
			if !env.IsWorkflowCompleted() || (env.GetWorkflowError() != nil) != scenario.workflowError || stub.attempts != scenario.attempts || stub.finished != scenario.finished || stub.outcome.Retryable != scenario.retryable {
				t.Fatalf("attempts=%d finished=%v outcome=%+v workflow=%v", stub.attempts, stub.finished, stub.outcome, env.GetWorkflowError())
			}
		})
	}
}

type thumbnailDispatchStub struct {
	acknowledge func(m.DocumentThumbnailJob, string) error
	released    bool
}

func (s *thumbnailDispatchStub) Discover(context.Context) error { return nil }
func (s *thumbnailDispatchStub) Claim(context.Context, string) ([]m.DocumentThumbnailJob, error) {
	return nil, nil
}
func (s *thumbnailDispatchStub) Acknowledge(_ context.Context, j m.DocumentThumbnailJob, run string) error {
	return s.acknowledge(j, run)
}
func (s *thumbnailDispatchStub) Release(context.Context, m.DocumentThumbnailJob) error {
	s.released = true
	return nil
}
func (s *thumbnailDispatchStub) Pending(context.Context) ([]m.DocumentThumbnailJob, error) {
	return nil, nil
}
func (s *thumbnailDispatchStub) Resolve(context.Context, m.DocumentThumbnailJob, string, bool, bool) error {
	return nil
}
func thumbnailDeliveryFixture() (m.DocumentThumbnailJob, *workflowservice.DescribeWorkflowExecutionResponse) {
	j := m.DocumentThumbnailJob{ID: "thumbnail-job", AccountID: "account", DocumentID: "document", SourceSHA256: "sha", RendererRevision: 1, Attempt: 1, WorkflowID: "document-thumbnail-v1/thumbnail-job", TaskQueue: "thumbnail-queue", LeaseToken: "lease", PermitEnd: time.Now().Add(time.Minute)}
	return j, &workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: &workflowpb.WorkflowExecutionInfo{Execution: &commonpb.WorkflowExecution{WorkflowId: j.WorkflowID, RunId: "run"}, Type: &commonpb.WorkflowType{Name: w.DocumentThumbnailWorkflowName}, TaskQueue: j.TaskQueue, Status: enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING}}
}
func thumbnailStartEvent(t *testing.T, j m.DocumentThumbnailJob) *historypb.HistoryEvent {
	t.Helper()
	payload, err := converter.GetDefaultDataConverter().ToPayloads(thumbnailJobRequestMapper(j))
	if err != nil {
		t.Fatal(err)
	}
	return &historypb.HistoryEvent{Attributes: &historypb.HistoryEvent_WorkflowExecutionStartedEventAttributes{WorkflowExecutionStartedEventAttributes: &historypb.WorkflowExecutionStartedEventAttributes{WorkflowType: &commonpb.WorkflowType{Name: w.DocumentThumbnailWorkflowName}, TaskQueue: &taskqueuepb.TaskQueue{Name: j.TaskQueue}, Input: payload}}}
}
func TestThumbnailDeliveryRecoversLostAcknowledgement(t *testing.T) {
	j, response := thumbnailDeliveryFixture()
	acks := 0
	service := &thumbnailDispatchStub{acknowledge: func(got m.DocumentThumbnailJob, run string) error {
		if got.LeaseToken != j.LeaseToken || run != "run" {
			t.Fatal("lost exact lease or run")
		}
		acks++
		if acks == 1 {
			return errors.New("database unavailable after start")
		}
		return nil
	}}
	remote := mocks.NewClient(t)
	run := mocks.NewWorkflowRun(t)
	run.On("GetID").Return(j.WorkflowID)
	run.On("GetRunID").Return("run")
	remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(j)).Return(run, nil).Once()
	remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(j)).Return(nil, &serviceerror.WorkflowExecutionAlreadyStarted{RunId: "run"}).Once()
	remote.On("DescribeWorkflowExecution", mock.Anything, j.WorkflowID, "run").Return(response, nil).Once()
	history := mocks.NewHistoryEventIterator(t)
	history.On("HasNext").Return(true).Once()
	history.On("Next").Return(thumbnailStartEvent(t, j), nil).Once()
	remote.On("GetWorkflowHistory", mock.Anything, j.WorkflowID, "run", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
	dispatcher := NewDocumentThumbnailDispatcher(service, remote, j.TaskQueue, slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
	if err := dispatcher.deliver(t.Context(), j); err == nil {
		t.Fatal("lost acknowledgement ignored")
	}
	if err := dispatcher.deliver(t.Context(), j); err != nil || acks != 2 {
		t.Fatalf("recovery failed: %v", err)
	}
}
func TestThumbnailDeliveryRejectsForeignStartInput(t *testing.T) {
	j, response := thumbnailDeliveryFixture()
	service := &thumbnailDispatchStub{acknowledge: func(m.DocumentThumbnailJob, string) error { t.Fatal("foreign execution adopted"); return nil }}
	remote := mocks.NewClient(t)
	remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(j)).Return(nil, &serviceerror.WorkflowExecutionAlreadyStarted{RunId: "run"}).Once()
	remote.On("DescribeWorkflowExecution", mock.Anything, j.WorkflowID, "run").Return(response, nil).Once()
	foreign := j
	foreign.SourceSHA256 = "other source"
	history := mocks.NewHistoryEventIterator(t)
	history.On("HasNext").Return(true).Once()
	history.On("Next").Return(thumbnailStartEvent(t, foreign), nil).Once()
	remote.On("GetWorkflowHistory", mock.Anything, j.WorkflowID, "run", false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT).Return(history).Once()
	dispatcher := NewDocumentThumbnailDispatcher(service, remote, j.TaskQueue, slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
	if err := dispatcher.deliver(t.Context(), j); err == nil || !service.released {
		t.Fatalf("foreign input not rejected: %v", err)
	}
}
