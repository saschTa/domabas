package temporal

import (
	"context"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	paperlessworkflows "github.com/domabas/domabas/backend/internal/domain/paperless/workflows"
	"github.com/stretchr/testify/mock"
	common "go.temporal.io/api/common/v1"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	workflowapi "go.temporal.io/api/workflow/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/mocks"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type dispatchRepository struct {
	execution *m.PaperlessExecution
	failure   string
	closed    bool
}

func (r *dispatchRepository) Next(context.Context) (*m.PaperlessExecution, error) {
	return r.execution, nil
}

func (r *dispatchRepository) Fail(_ context.Context, _ string, code string) error {
	r.failure = code
	return nil
}

func (r *dispatchRepository) Closed(context.Context, string) error {
	r.closed = true
	return nil
}

func TestDispatcherReadinessIsEstablishedDuringStartupAndClearedOnShutdown(t *testing.T) {
	d := NewPaperlessImportDispatcher(&dispatchRepository{}, &mocks.Client{})
	if d.Ping() == nil {
		t.Fatal("unstarted dispatcher reported ready")
	}
	startup, cancel := context.WithCancel(t.Context())
	if err := d.Start(startup); err != nil {
		t.Fatal(err)
	}
	cancel()
	if err := d.Ping(); err != nil {
		t.Fatal("startup deadline leaked into dispatcher lifetime", err)
	}
	d.Close()
	d.Close()
	if d.Ping() == nil {
		t.Fatal("closed dispatcher reported ready")
	}
	NewPaperlessImportDispatcher(&dispatchRepository{}, &mocks.Client{}).Close()
}

func TestDispatcherReconcilesClosureBeforeReleasingAdmission(t *testing.T) {
	for _, test := range []struct {
		name   string
		status enums.WorkflowExecutionStatus
		age    time.Duration
		closed bool
	}{
		{"running", enums.WORKFLOW_EXECUTION_STATUS_RUNNING, 0, false},
		{"completed", enums.WORKFLOW_EXECUTION_STATUS_COMPLETED, 0, true},
		{"terminated activity draining", enums.WORKFLOW_EXECUTION_STATUS_TERMINATED, time.Second, false},
		{"terminated activity expired", enums.WORKFLOW_EXECUTION_STATUS_TERMINATED, 2 * time.Minute, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			r := &dispatchRepository{execution: &m.PaperlessExecution{ID: "owned", TaskQueue: "owned-queue", FirstStart: time.Now()}}
			remote := &mocks.Client{}
			remote.On("DescribeWorkflowExecution", mock.Anything, "domabas-paperless-owned", "").Return(&workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: &workflowapi.WorkflowExecutionInfo{
				TaskQueue: "owned-queue", Type: &common.WorkflowType{Name: paperlessworkflows.PaperlessImportWorkflowName}, Status: test.status, CloseTime: timestamppb.New(time.Now().Add(-test.age)),
			}}, nil).Once()
			if err := NewPaperlessImportDispatcher(r, remote).tick(t.Context()); err != nil {
				t.Fatal(err)
			}
			if r.closed != test.closed || (r.failure != "") != (test.status != enums.WORKFLOW_EXECUTION_STATUS_RUNNING) {
				t.Fatal("incorrect closure reconciliation", r.closed, r.failure)
			}
			remote.AssertExpectations(t)
		})
	}
}

func TestDispatcherBoundsUncertainStartsAndRejectsForeignExecutions(t *testing.T) {
	for _, test := range []string{"ambiguous start", "expired start", "foreign execution"} {
		t.Run(test, func(t *testing.T) {
			r := &dispatchRepository{execution: &m.PaperlessExecution{ID: "owned", TaskQueue: "owned-queue", FirstStart: time.Now()}}
			remote := &mocks.Client{}
			if test == "foreign execution" {
				remote.On("DescribeWorkflowExecution", mock.Anything, "domabas-paperless-owned", "").Return(&workflowservice.DescribeWorkflowExecutionResponse{WorkflowExecutionInfo: &workflowapi.WorkflowExecutionInfo{TaskQueue: "foreign"}}, nil).Once()
			} else {
				remote.On("DescribeWorkflowExecution", mock.Anything, "domabas-paperless-owned", "").Return(nil, serviceerror.NewNotFound("missing")).Once()
				if test == "expired start" {
					r.execution.FirstStart = time.Now().Add(-21 * time.Hour)
				} else {
					remote.On("ExecuteWorkflow", mock.Anything, mock.MatchedBy(func(o client.StartWorkflowOptions) bool {
						return o.ID == "domabas-paperless-owned" && o.TaskQueue == "owned-queue" && o.WorkflowIDReusePolicy == enums.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE && o.WorkflowExecutionTimeout == 7*24*time.Hour
					}), paperlessworkflows.PaperlessImportWorkflowName, "owned").Return(nil, serviceerror.NewWorkflowExecutionAlreadyStarted("accepted earlier", "request", "run")).Once()
				}
			}
			err := NewPaperlessImportDispatcher(r, remote).tick(t.Context())
			if (err != nil) != (test == "foreign execution") || r.closed != (test == "expired start") || (r.failure == "delivery_expired") != (test == "expired start") {
				t.Fatal("unsafe execution reconciliation", err, r.closed, r.failure)
			}
			remote.AssertExpectations(t)
		})
	}
}
