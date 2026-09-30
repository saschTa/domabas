package temporal

import (
	"bytes"
	"context"
	"errors"
	"sync"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"
	"github.com/google/uuid"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	sdk "go.temporal.io/sdk/temporal"
)

type EmailPollService interface {
	Page(context.Context, m.EmailAttempt) (m.EmailPageResult, error)
	Fail(context.Context, m.EmailAttempt, string) error
}

type EmailTemporalClient interface {
	ExecuteWorkflow(context.Context, client.StartWorkflowOptions, interface{}, ...interface{}) (client.WorkflowRun, error)
	DescribeWorkflowExecution(context.Context, string, string) (*workflowservice.DescribeWorkflowExecutionResponse, error)
	GetWorkflowHistory(context.Context, string, string, bool, enums.HistoryEventFilterType) client.HistoryEventIterator
}

type EmailPollActivities struct {
	service EmailPollService
	client  EmailTemporalClient
	ctx     context.Context
	cancel  context.CancelFunc
	mutex   sync.Mutex
	closed  bool
	active  sync.WaitGroup
}

func NewEmailPollActivities(service EmailPollService, client EmailTemporalClient) *EmailPollActivities {
	ctx, cancel := context.WithCancel(context.Background())
	return &EmailPollActivities{service: service, client: client, ctx: ctx, cancel: cancel}
}

func (a *EmailPollActivities) Close() {
	a.mutex.Lock()
	a.closed = true
	a.cancel()
	a.mutex.Unlock()
	a.active.Wait()
}

func describeExecution(ctx context.Context, c EmailTemporalClient, runID, workflowRunID, queue string) (*workflowservice.DescribeWorkflowExecutionResponse, error) {
	workflowID := "domabas-email-" + runID
	response, err := c.DescribeWorkflowExecution(ctx, workflowID, workflowRunID)
	if err != nil {
		return nil, err
	}
	info := response.GetWorkflowExecutionInfo()
	if info.GetExecution().GetWorkflowId() != workflowID || info.GetExecution().GetRunId() == "" || workflowRunID != "" && info.GetExecution().GetRunId() != workflowRunID || info.GetType().GetName() != emailworkflows.EmailPollWorkflowName || info.GetTaskQueue() != queue {
		return nil, errors.New("email execution ownership mismatch")
	}
	return response, nil
}

func verifyExecution(ctx context.Context, c EmailTemporalClient, runID, workflowRunID, queue string) (*workflowservice.DescribeWorkflowExecutionResponse, error) {
	response, err := describeExecution(ctx, c, runID, workflowRunID, queue)
	if err != nil {
		return nil, err
	}
	info := response.GetWorkflowExecutionInfo()
	history := c.GetWorkflowHistory(ctx, info.GetExecution().GetWorkflowId(), info.GetExecution().GetRunId(), false, enums.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	if !history.HasNext() {
		return nil, errors.New("email workflow start unavailable")
	}
	event, err := history.Next()
	if err != nil {
		return nil, err
	}
	started := event.GetWorkflowExecutionStartedEventAttributes()
	expected, err := converter.GetDefaultDataConverter().ToPayloads(emailworkflows.EmailPollWorkflowInput{RunID: runID})
	if err != nil {
		return nil, err
	}
	if started == nil || len(started.GetInput().GetPayloads()) != len(expected.GetPayloads()) {
		return nil, errors.New("email workflow input mismatch")
	}
	for i, payload := range expected.GetPayloads() {
		if !bytes.Equal(payload.GetData(), started.GetInput().GetPayloads()[i].GetData()) {
			return nil, errors.New("email workflow input mismatch")
		}
	}
	return response, nil
}

func (a *EmailPollActivities) Page(ctx context.Context, input emailworkflows.EmailPollPageInput) (m.EmailPageResult, error) {
	a.mutex.Lock()
	if a.closed {
		a.mutex.Unlock()
		return m.EmailPageResult{}, sdk.NewNonRetryableApplicationError("email worker stopping", "cancelled", nil)
	}
	a.active.Add(1)
	a.mutex.Unlock()
	defer a.active.Done()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stop := context.AfterFunc(a.ctx, cancel)
	defer stop()
	info := activity.GetInfo(ctx)
	heartbeatDone := make(chan struct{})
	heartbeatStopped := make(chan struct{})
	go func() {
		defer close(heartbeatStopped)
		timer := time.NewTicker(2 * time.Second)
		defer timer.Stop()
		for {
			select {
			case <-timer.C:
				activity.RecordHeartbeat(ctx, input.RunID, input.PageIndex, info.Attempt)
			case <-ctx.Done():
				return
			case <-heartbeatDone:
				return
			}
		}
	}()
	defer func() { close(heartbeatDone); <-heartbeatStopped }()
	if info.WorkflowExecution.ID != "domabas-email-"+input.RunID {
		return m.EmailPageResult{}, sdk.NewNonRetryableApplicationError("invalid email workflow identity", "invalid_identity", nil)
	}
	response, err := verifyExecution(ctx, a.client, input.RunID, info.WorkflowExecution.RunID, info.TaskQueue)
	if err != nil {
		return m.EmailPageResult{}, err
	}
	attempt := m.EmailAttempt{RunID: input.RunID, WorkflowID: info.WorkflowExecution.ID, WorkflowRunID: info.WorkflowExecution.RunID, TaskQueue: info.TaskQueue, ActivityID: info.ActivityID, Token: uuid.NewString(), PageIndex: input.PageIndex, Number: int(info.Attempt), Deadline: info.Deadline, ExecutionStartedAt: response.GetWorkflowExecutionInfo().GetStartTime().AsTime()}
	result, err := a.service.Page(ctx, attempt)
	if err == nil {
		return result, nil
	}
	code := "poll_failed"
	retry := true
	var failure m.EmailFailure
	if errors.As(err, &failure) {
		code = failure.Code
		retry = failure.Retryable
	}
	if errors.Is(err, m.ErrStaleAttempt) || errors.Is(err, m.ErrForbidden) {
		code = "authority_changed"
		retry = false
	}
	if !retry || info.Attempt >= 2 {
		_ = a.service.Fail(ctx, attempt, code)
	}
	if !retry {
		return result, sdk.NewNonRetryableApplicationError(code, code, nil)
	}
	return result, sdk.NewApplicationError(code, code)
}
