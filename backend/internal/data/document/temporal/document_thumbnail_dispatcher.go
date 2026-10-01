package temporal

import (
	"bytes"
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	w "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	schedulermodels "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	enumspb "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"
)

type DocumentThumbnailDispatchService interface {
	Discover(context.Context) error
	Claim(context.Context, string) ([]m.DocumentThumbnailJob, error)
	Acknowledge(context.Context, m.DocumentThumbnailJob, string) error
	Release(context.Context, m.DocumentThumbnailJob) error
	Pending(context.Context) ([]m.DocumentThumbnailJob, error)
	Resolve(context.Context, m.DocumentThumbnailJob, string, bool, bool) error
}
type DocumentThumbnailDispatcher struct {
	service                     DocumentThumbnailDispatchService
	client                      DocumentDispatchClient
	queue                       string
	logger                      *slog.Logger
	retention                   func(context.Context) error
	mu                          sync.Mutex
	started, closed             bool
	cancel                      context.CancelFunc
	workers                     sync.WaitGroup
	running                     atomic.Bool
	deliveryTick, reconcileTick atomic.Int64
}

func NewDocumentThumbnailDispatcher(service DocumentThumbnailDispatchService, c DocumentDispatchClient, queue string, logger *slog.Logger, retention func(context.Context) error) *DocumentThumbnailDispatcher {
	return &DocumentThumbnailDispatcher{service: service, client: c, queue: queue, logger: logger, retention: retention}
}
func (d *DocumentThumbnailDispatcher) Start() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.started || d.closed {
		return errors.New("thumbnail dispatcher cannot start twice")
	}
	if d.service == nil || d.client == nil || d.queue == "" || d.logger == nil {
		return errors.New("thumbnail dispatcher dependencies are required")
	}
	ctx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	d.started = true
	d.running.Store(true)
	d.deliveryTick.Store(time.Now().UnixNano())
	d.reconcileTick.Store(time.Now().UnixNano())
	d.workers.Add(2)
	go d.loop(ctx, 2*time.Second, &d.deliveryTick, d.dispatch)
	go d.loop(ctx, 15*time.Second, &d.reconcileTick, d.reconcile)
	return nil
}
func (d *DocumentThumbnailDispatcher) Ping() error {
	if !d.running.Load() || time.Since(time.Unix(0, d.deliveryTick.Load())) > 45*time.Second || time.Since(time.Unix(0, d.reconcileTick.Load())) > 45*time.Second {
		return errors.New("thumbnail dispatcher is not running")
	}
	return nil
}
func (d *DocumentThumbnailDispatcher) Close() {
	d.mu.Lock()
	d.closed = true
	d.running.Store(false)
	if d.cancel != nil {
		d.cancel()
	}
	d.mu.Unlock()
	d.workers.Wait()
}
func (d *DocumentThumbnailDispatcher) loop(ctx context.Context, interval time.Duration, tick *atomic.Int64, run func(context.Context) error) {
	defer d.workers.Done()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		operation, cancel := context.WithTimeout(ctx, 12*time.Second)
		err := run(operation)
		cancel()
		tick.Store(time.Now().UnixNano())
		if err != nil && ctx.Err() == nil {
			d.logger.WarnContext(ctx, "thumbnail delivery or reconciliation will retry", "task_queue", d.queue, "error", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
func (d *DocumentThumbnailDispatcher) dispatch(ctx context.Context) error {
	if d.retention != nil {
		if err := d.retention(ctx); err != nil {
			return err
		}
	}
	if err := d.service.Discover(ctx); err != nil {
		return err
	}
	for range schedulermodels.SchedulerMaximumLimit {
		if err := ctx.Err(); err != nil {
			return err
		}
		jobs, err := d.service.Claim(ctx, d.queue)
		if err != nil {
			return err
		}
		if len(jobs) == 0 {
			return nil
		}
		for _, j := range jobs {
			if err = d.deliver(ctx, j); err != nil {
				return err
			}
		}
	}
	return nil
}
func (d *DocumentThumbnailDispatcher) deliver(ctx context.Context, j m.DocumentThumbnailJob) error {
	if j.WorkflowID != "document-thumbnail-v1/"+j.ID || j.TaskQueue == "" || !time.Now().Before(j.PermitEnd) {
		return d.service.Release(ctx, j)
	}
	operation, cancel := context.WithDeadline(ctx, j.PermitEnd)
	run, err := d.client.ExecuteWorkflow(operation, client.StartWorkflowOptions{ID: j.WorkflowID, TaskQueue: j.TaskQueue, WorkflowExecutionTimeout: 15 * time.Minute, WorkflowIDReusePolicy: enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE, WorkflowIDConflictPolicy: enumspb.WORKFLOW_ID_CONFLICT_POLICY_FAIL, WorkflowExecutionErrorWhenAlreadyStarted: true}, w.DocumentThumbnailWorkflowName, thumbnailJobRequestMapper(j))
	cancel()
	runID := ""
	if err == nil {
		if run == nil || run.GetID() != j.WorkflowID || run.GetRunID() == "" {
			err = errors.New("unexpected thumbnail execution identity")
		} else {
			runID = run.GetRunID()
		}
	}
	var duplicate *serviceerror.WorkflowExecutionAlreadyStarted
	if errors.As(err, &duplicate) {
		j.RunID = duplicate.RunId
		response, e := d.match(ctx, j)
		if e == nil {
			runID = response.GetWorkflowExecutionInfo().GetExecution().GetRunId()
			err = nil
		} else {
			err = e
		}
	}
	if err != nil {
		if e := d.service.Release(ctx, j); e != nil {
			return e
		}
		return err
	}
	return d.service.Acknowledge(ctx, j, runID)
}
func (d *DocumentThumbnailDispatcher) match(ctx context.Context, j m.DocumentThumbnailJob) (*workflowservice.DescribeWorkflowExecutionResponse, error) {
	response, err := d.client.DescribeWorkflowExecution(ctx, j.WorkflowID, j.RunID)
	if err != nil {
		return nil, err
	}
	info := response.GetWorkflowExecutionInfo()
	if j.WorkflowID != "document-thumbnail-v1/"+j.ID || info.GetExecution().GetWorkflowId() != j.WorkflowID || info.GetExecution().GetRunId() == "" || (j.RunID != "" && j.RunID != info.GetExecution().GetRunId()) || info.GetType().GetName() != w.DocumentThumbnailWorkflowName || info.GetTaskQueue() != j.TaskQueue {
		return nil, errors.New("thumbnail execution ownership mismatch")
	}
	history := d.client.GetWorkflowHistory(ctx, j.WorkflowID, info.GetExecution().GetRunId(), false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	if !history.HasNext() {
		return nil, errors.New("thumbnail start history unavailable")
	}
	event, err := history.Next()
	if err != nil {
		return nil, err
	}
	started := event.GetWorkflowExecutionStartedEventAttributes()
	expected, err := converter.GetDefaultDataConverter().ToPayloads(thumbnailJobRequestMapper(j))
	if err != nil {
		return nil, err
	}
	actual := started.GetInput().GetPayloads()
	if started.GetWorkflowType().GetName() != w.DocumentThumbnailWorkflowName || started.GetTaskQueue().GetName() != j.TaskQueue || len(actual) != 1 || !bytes.Equal(actual[0].GetData(), expected.Payloads[0].GetData()) || !bytes.Equal(actual[0].GetMetadata()["encoding"], expected.Payloads[0].GetMetadata()["encoding"]) {
		return nil, errors.New("thumbnail execution input mismatch")
	}
	return response, nil
}
func (d *DocumentThumbnailDispatcher) reconcile(ctx context.Context) error {
	jobs, err := d.service.Pending(ctx)
	if err != nil {
		return err
	}
	var wait sync.WaitGroup
	limit := make(chan struct{}, 4)
	failures := make(chan error, len(jobs))
	for _, j := range jobs {
		select {
		case limit <- struct{}{}:
		case <-ctx.Done():
			wait.Wait()
			return ctx.Err()
		}
		wait.Go(func() {
			defer func() { <-limit }()
			operation, cancel := context.WithTimeout(ctx, 2*time.Second)
			defer cancel()
			response, e := d.match(operation, j)
			if e != nil {
				var missing *serviceerror.NotFound
				if errors.As(e, &missing) {
					e = d.service.Resolve(ctx, j, "", false, true)
				}
				if e != nil {
					failures <- e
				}
				return
			}
			info := response.GetWorkflowExecutionInfo()
			closed := info.GetStatus() != enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING && info.GetStatus() != enumspb.WORKFLOW_EXECUTION_STATUS_UNSPECIFIED
			if e = d.service.Resolve(ctx, j, info.GetExecution().GetRunId(), closed, false); e != nil {
				failures <- e
			}
		})
	}
	wait.Wait()
	close(failures)
	for err := range failures {
		return err
	}
	return nil
}
