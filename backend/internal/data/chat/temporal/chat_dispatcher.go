package temporal

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	w "github.com/domabas/domabas/backend/internal/domain/chat/workflows"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/temporal"
)

type ChatOutboxService interface {
	Dispatch(context.Context) ([]m.ChatDispatch, error)
	Acknowledge(context.Context, m.ChatDispatch, string) error
	ReleaseDelivery(context.Context, m.ChatDispatch) error
	Closed(context.Context, m.ChatDispatch, string) error
}

type ChatDispatchClient interface {
	CancelWorkflow(context.Context, string, string) error
	ExecuteWorkflow(context.Context, client.StartWorkflowOptions, interface{}, ...interface{}) (client.WorkflowRun, error)
	DescribeWorkflowExecution(context.Context, string, string) (*workflowservice.DescribeWorkflowExecutionResponse, error)
	GetWorkflowHistory(context.Context, string, string, bool, enums.HistoryEventFilterType) client.HistoryEventIterator
}

type ChatDispatcher struct {
	service         ChatOutboxService
	client          ChatDispatchClient
	queue           string
	logger          *slog.Logger
	retention       func(context.Context) error
	mu              sync.Mutex
	started, closed bool
	cancel          context.CancelFunc
	active          sync.WaitGroup
	running         atomic.Bool
	tick            atomic.Int64
	now             func() time.Time
}

func NewChatDispatcher(service ChatOutboxService, temporalClient ChatDispatchClient, queue string, logger *slog.Logger, retention ...func(context.Context) error) *ChatDispatcher {
	d := &ChatDispatcher{service: service, client: temporalClient, queue: queue, logger: logger, now: time.Now}
	if len(retention) > 0 {
		d.retention = retention[0]
	}
	return d
}

func (d *ChatDispatcher) Start(startup ...context.Context) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.started || d.closed || d.service == nil || d.client == nil || d.queue == "" || d.logger == nil {
		return errors.New("chat dispatcher cannot start")
	}
	initial := context.Background()
	if len(startup) > 0 {
		initial = startup[0]
	}
	probe, stop := context.WithTimeout(initial, 12*time.Second)
	err := d.dispatch(probe)
	stop()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	d.started = true
	d.running.Store(true)
	d.tick.Store(d.now().UnixNano())
	d.active.Add(1)
	go d.loop(ctx)
	return nil
}

func (d *ChatDispatcher) Close() {
	d.mu.Lock()
	d.closed = true
	d.running.Store(false)
	if d.cancel != nil {
		d.cancel()
	}
	d.mu.Unlock()
	d.active.Wait()
}

func (d *ChatDispatcher) Ping() error {
	if !d.running.Load() || d.now().Sub(time.Unix(0, d.tick.Load())) > 45*time.Second {
		return errors.New("chat dispatcher is not running")
	}
	return nil
}

func (d *ChatDispatcher) loop(ctx context.Context) {
	defer d.active.Done()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		iteration, cancel := context.WithTimeout(ctx, 12*time.Second)
		err := d.dispatch(iteration)
		cancel()
		if err == nil {
			d.tick.Store(d.now().UnixNano())
		}
		if err != nil && ctx.Err() == nil {
			var databaseError interface{ SQLState() string }
			sqlState := ""
			if errors.As(err, &databaseError) {
				sqlState = databaseError.SQLState()
			}
			d.logger.WarnContext(ctx, "chat delivery or reconciliation will retry", "task_queue", d.queue, "error_type", fmt.Sprintf("%T", err), "error_code", serviceerror.ToStatus(err).Code().String(), "sql_state", sqlState)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (d *ChatDispatcher) dispatch(ctx context.Context) error {
	if d.retention != nil {
		if err := d.retention(ctx); err != nil {
			return err
		}
	}
	jobs, err := d.service.Dispatch(ctx)
	if err != nil {
		return err
	}
	var active sync.WaitGroup
	failures := make(chan error, len(jobs))
	permits := make(chan struct{}, 3)
	for _, job := range jobs {
		select {
		case permits <- struct{}{}:
		case <-ctx.Done():
			active.Wait()
			return ctx.Err()
		}
		active.Go(func() {
			defer func() { <-permits }()
			if err := d.deliver(ctx, job); err != nil {
				_ = d.service.ReleaseDelivery(ctx, job)
				failures <- err
			}
		})
	}
	active.Wait()
	close(failures)
	for err := range failures {
		return err
	}
	return nil
}

func ChatWorkflowID(turnID string) string { return "domabas-chat-" + turnID }

func (d *ChatDispatcher) deliver(ctx context.Context, job m.ChatDispatch) error {
	request := w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID}
	if !validChatRequest(request) || job.WorkflowID != ChatWorkflowID(job.TurnID) || job.TaskQueue != d.queue || job.DeliveryToken == "" || job.FirstStartAt.IsZero() {
		return errors.New("chat delivery ownership is invalid")
	}
	description, err := d.describe(ctx, job)
	if err == nil {
		return d.reconcile(ctx, job, description)
	}
	var missing *serviceerror.NotFound
	if !errors.As(err, &missing) {
		return err
	}
	age := d.now().Sub(job.FirstStartAt)
	if job.RunID != "" || age >= 20*time.Hour {
		if age >= 24*time.Hour+m.ChatActivityLease {
			return d.service.Closed(ctx, job, "execution_lost")
		}
		return d.service.ReleaseDelivery(ctx, job)
	}
	if job.CancelRequested {
		return d.service.Closed(ctx, job, "chat_cancelled")
	}
	operation, cancel := context.WithTimeout(ctx, 4*time.Second)
	run, err := d.client.ExecuteWorkflow(operation, client.StartWorkflowOptions{
		ID: job.WorkflowID, TaskQueue: job.TaskQueue,
		WorkflowExecutionTimeout:                 24 * time.Hour,
		WorkflowIDReusePolicy:                    enums.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE,
		WorkflowIDConflictPolicy:                 enums.WORKFLOW_ID_CONFLICT_POLICY_FAIL,
		WorkflowExecutionErrorWhenAlreadyStarted: true,
		Priority:                                 temporal.Priority{PriorityKey: 5},
	}, w.ChatTurnWorkflowName, request)
	cancel()
	if err == nil {
		if run == nil || run.GetID() != job.WorkflowID || run.GetRunID() == "" {
			return errors.New("chat workflow start returned invalid identity")
		}
		return d.service.Acknowledge(ctx, job, run.GetRunID())
	}
	var duplicate *serviceerror.WorkflowExecutionAlreadyStarted
	if errors.As(err, &duplicate) {
		job.RunID = duplicate.RunId
		if job.RunID == "" {
			return errors.New("chat duplicate execution identity is missing")
		}
		description, err = d.describe(ctx, job)
		if err == nil {
			return d.reconcile(ctx, job, description)
		}
	}
	return err
}

func (d *ChatDispatcher) describe(ctx context.Context, job m.ChatDispatch) (*workflowservice.DescribeWorkflowExecutionResponse, error) {
	operation, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	description, err := d.client.DescribeWorkflowExecution(operation, job.WorkflowID, job.RunID)
	if err != nil {
		return nil, err
	}
	info := description.GetWorkflowExecutionInfo()
	if info.GetExecution().GetWorkflowId() != job.WorkflowID || info.GetExecution().GetRunId() == "" || (job.RunID != "" && info.GetExecution().GetRunId() != job.RunID) || info.GetType().GetName() != w.ChatTurnWorkflowName || info.GetTaskQueue() != job.TaskQueue {
		return nil, errors.New("chat workflow ownership does not match")
	}
	history := d.client.GetWorkflowHistory(operation, job.WorkflowID, info.GetExecution().GetRunId(), false, enums.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	if !history.HasNext() {
		return nil, errors.New("chat workflow start is unavailable")
	}
	event, err := history.Next()
	if err != nil {
		return nil, err
	}
	started := event.GetWorkflowExecutionStartedEventAttributes()
	expected, err := converter.GetDefaultDataConverter().ToPayloads(w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID})
	if err != nil {
		return nil, errors.New("chat workflow request encoding failed")
	}
	actual := started.GetInput().GetPayloads()
	if started.GetWorkflowType().GetName() != w.ChatTurnWorkflowName || started.GetTaskQueue().GetName() != job.TaskQueue || len(actual) != 1 || !bytes.Equal(actual[0].GetData(), expected.Payloads[0].GetData()) || !bytes.Equal(actual[0].GetMetadata()["encoding"], expected.Payloads[0].GetMetadata()["encoding"]) {
		return nil, errors.New("chat workflow request does not match")
	}
	return description, nil
}

func (d *ChatDispatcher) reconcile(ctx context.Context, job m.ChatDispatch, description *workflowservice.DescribeWorkflowExecutionResponse) error {
	info := description.GetWorkflowExecutionInfo()
	job.RunID = info.GetExecution().GetRunId()
	switch info.GetStatus() {
	case enums.WORKFLOW_EXECUTION_STATUS_RUNNING:
		if job.CancelRequested {
			operation, cancel := context.WithTimeout(ctx, 3*time.Second)
			err := d.client.CancelWorkflow(operation, job.WorkflowID, job.RunID)
			cancel()
			if err != nil {
				return err
			}
		}
		return d.service.Acknowledge(ctx, job, job.RunID)
	case enums.WORKFLOW_EXECUTION_STATUS_CANCELED:
		return d.service.Closed(ctx, job, "chat_cancelled")
	case enums.WORKFLOW_EXECUTION_STATUS_TIMED_OUT:
		return d.service.Closed(ctx, job, "chat_timeout")
	case enums.WORKFLOW_EXECUTION_STATUS_COMPLETED, enums.WORKFLOW_EXECUTION_STATUS_FAILED, enums.WORKFLOW_EXECUTION_STATUS_TERMINATED:
		return d.service.Closed(ctx, job, "chat_failed")
	default:
		return errors.New("chat workflow has an unexpected execution status")
	}
}
