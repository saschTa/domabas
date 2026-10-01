package temporal

import (
	"context"
	"errors"
	"fmt"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	w "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	schedulermodels "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
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
	discover    func(context.Context) error
	claim       func(context.Context, string) ([]m.DocumentThumbnailJob, error)
	acknowledge func(m.DocumentThumbnailJob, string) error
	released    bool
}

func (s *thumbnailDispatchStub) Discover(ctx context.Context) error {
	if s.discover != nil {
		return s.discover(ctx)
	}
	return nil
}
func (s *thumbnailDispatchStub) Claim(ctx context.Context, queue string) ([]m.DocumentThumbnailJob, error) {
	if s.claim != nil {
		return s.claim(ctx, queue)
	}
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

func TestThumbnailDispatchFillsAvailableSlotsInOnePass(t *testing.T) {
	for _, available := range []int{0, 3, 21, schedulermodels.SchedulerMaximumLimit + 1} {
		t.Run(fmt.Sprintf("available_%d", available), func(t *testing.T) {
			remote := mocks.NewClient(t)
			claims, acknowledgements, discoveries, retentionChecks := 0, 0, 0, 0
			service := &thumbnailDispatchStub{
				discover: func(context.Context) error {
					discoveries++
					return nil
				},
				claim: func(_ context.Context, queue string) ([]m.DocumentThumbnailJob, error) {
					if queue != "thumbnail-queue" || claims != acknowledgements {
						t.Fatal("next claim did not follow acknowledgement on the expected queue")
					}
					claims++
					if claims > available {
						return nil, nil
					}
					job, _ := thumbnailDeliveryFixture()
					job.ID = fmt.Sprintf("thumbnail-job-%d", claims)
					job.WorkflowID = "document-thumbnail-v1/" + job.ID
					run := mocks.NewWorkflowRun(t)
					run.On("GetID").Return(job.WorkflowID).Once()
					run.On("GetRunID").Return(job.ID + "-run").Twice()
					remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(job)).Return(run, nil).Once()
					return []m.DocumentThumbnailJob{job}, nil
				},
				acknowledge: func(job m.DocumentThumbnailJob, run string) error {
					if run != job.ID+"-run" {
						t.Fatal("acknowledged another workflow run")
					}
					acknowledgements++
					return nil
				},
			}
			dispatcher := NewDocumentThumbnailDispatcher(service, remote, "thumbnail-queue", slog.New(slog.NewTextHandler(io.Discard, nil)), func(context.Context) error {
				retentionChecks++
				return nil
			})
			if err := dispatcher.dispatch(t.Context()); err != nil {
				t.Fatal(err)
			}
			wantStarts := min(available, schedulermodels.SchedulerMaximumLimit)
			wantClaims := min(available+1, schedulermodels.SchedulerMaximumLimit)
			if acknowledgements != wantStarts || claims != wantClaims || discoveries != 1 || retentionChecks != 1 || service.released {
				t.Fatalf("starts=%d claims=%d discoveries=%d retention=%d released=%v; want starts=%d claims=%d", acknowledgements, claims, discoveries, retentionChecks, service.released, wantStarts, wantClaims)
			}
		})
	}
}

func TestThumbnailDispatchStopsOnFailureOrCancellation(t *testing.T) {
	failure := errors.New("thumbnail dispatch unavailable")
	for _, scenario := range []string{"retention", "discovery", "claim", "delivery", "acknowledgement", "cancelled before claim", "cancelled after start"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			job, _ := thumbnailDeliveryFixture()
			remote := mocks.NewClient(t)
			claims, acknowledgements := 0, 0
			service := &thumbnailDispatchStub{
				discover: func(context.Context) error {
					if scenario == "discovery" {
						return failure
					}
					return nil
				},
				claim: func(context.Context, string) ([]m.DocumentThumbnailJob, error) {
					claims++
					if claims > 1 {
						t.Fatal("claimed more work after an error or cancellation")
					}
					if scenario == "claim" {
						return nil, failure
					}
					return []m.DocumentThumbnailJob{job}, nil
				},
				acknowledge: func(m.DocumentThumbnailJob, string) error {
					acknowledgements++
					if scenario == "acknowledgement" {
						return failure
					}
					cancel()
					return nil
				},
			}
			if scenario == "delivery" {
				remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(job)).Return(nil, failure).Once()
			}
			if scenario == "acknowledgement" || scenario == "cancelled after start" {
				run := mocks.NewWorkflowRun(t)
				run.On("GetID").Return(job.WorkflowID).Once()
				run.On("GetRunID").Return("run").Twice()
				remote.On("ExecuteWorkflow", mock.Anything, mock.Anything, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(job)).Return(run, nil).Once()
			}
			want := failure
			if scenario == "cancelled before claim" {
				cancel()
				want = context.Canceled
			}
			if scenario == "cancelled after start" {
				want = context.Canceled
			}
			dispatcher := NewDocumentThumbnailDispatcher(service, remote, job.TaskQueue, slog.New(slog.NewTextHandler(io.Discard, nil)), func(context.Context) error {
				if scenario == "retention" {
					return failure
				}
				return nil
			})
			if err := dispatcher.dispatch(ctx); !errors.Is(err, want) {
				t.Fatalf("dispatch error=%v; want %v", err, want)
			}
			wantClaims, wantAcknowledgements := 1, 0
			if scenario == "retention" || scenario == "discovery" || scenario == "cancelled before claim" {
				wantClaims = 0
			}
			if scenario == "acknowledgement" || scenario == "cancelled after start" {
				wantAcknowledgements = 1
			}
			if claims != wantClaims || acknowledgements != wantAcknowledgements || service.released != (scenario == "delivery") {
				t.Fatalf("claims=%d acknowledgements=%d released=%v", claims, acknowledgements, service.released)
			}
		})
	}
}
