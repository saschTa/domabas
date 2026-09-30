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

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	enumspb "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
)

type DocumentOutboxService interface {
	ResolveExecution(context.Context, document.DocumentPendingJob, string, string, bool) error
	Claim(context.Context, int, time.Duration, ...string) ([]document.DocumentOutboxLease, error)
	Acknowledge(context.Context, document.DocumentOutboxLease, string, string) error
	Release(context.Context, document.DocumentOutboxLease, time.Time) error
	Pending(context.Context, int) ([]document.DocumentPendingJob, error)
	Fail(context.Context, document.DocumentJob, string) error
	FailExpired(context.Context, document.DocumentJob, string) error
	ReapUploads(context.Context) error
}

type DocumentDispatchClient interface {
	CancelWorkflow(context.Context, string, string) error
	ExecuteWorkflow(context.Context, client.StartWorkflowOptions, interface{}, ...interface{}) (client.WorkflowRun, error)
	DescribeWorkflowExecution(context.Context, string, string) (*workflowservice.DescribeWorkflowExecutionResponse, error)
	GetWorkflowHistory(context.Context, string, string, bool, enumspb.HistoryEventFilterType) client.HistoryEventIterator
}

type DocumentIngestionDispatcher struct {
	retention     func(context.Context) error
	service       DocumentOutboxService
	client        DocumentDispatchClient
	queue         string
	logger        *slog.Logger
	mu            sync.Mutex
	started       bool
	closed        bool
	cancel        context.CancelFunc
	workers       sync.WaitGroup
	running       atomic.Bool
	deliveryTick  atomic.Int64
	reconcileTick atomic.Int64
	now           func() time.Time
}

func NewDocumentIngestionDispatcher(service DocumentOutboxService, temporalClient DocumentDispatchClient, queue string, logger *slog.Logger, retention ...func(context.Context) error) *DocumentIngestionDispatcher {
	var guard func(context.Context) error
	if len(retention) > 0 {
		guard = retention[0]
	}
	return &DocumentIngestionDispatcher{retention: guard, service: service, client: temporalClient, queue: queue, logger: logger, now: time.Now}
}

func (dispatcher *DocumentIngestionDispatcher) Start() error {
	dispatcher.mu.Lock()
	defer dispatcher.mu.Unlock()
	if dispatcher.started || dispatcher.closed {
		return errors.New("document dispatcher cannot be started twice")
	}
	if dispatcher.service == nil || dispatcher.client == nil || dispatcher.queue == "" || dispatcher.logger == nil {
		return errors.New("document dispatcher dependencies are required")
	}
	ctx, cancel := context.WithCancel(context.Background())
	dispatcher.cancel = cancel
	dispatcher.started = true
	dispatcher.deliveryTick.Store(dispatcher.now().UnixNano())
	dispatcher.reconcileTick.Store(dispatcher.now().UnixNano())
	dispatcher.running.Store(true)
	dispatcher.workers.Add(2)
	go dispatcher.loop(ctx, "dispatch", 2*time.Second, &dispatcher.deliveryTick, dispatcher.dispatch)
	go dispatcher.loop(ctx, "reconcile", 15*time.Second, &dispatcher.reconcileTick, dispatcher.reconcile)
	return nil
}

func (dispatcher *DocumentIngestionDispatcher) Ping() error {
	now := dispatcher.now()
	if !dispatcher.running.Load() || now.Sub(time.Unix(0, dispatcher.deliveryTick.Load())) > 45*time.Second || now.Sub(time.Unix(0, dispatcher.reconcileTick.Load())) > 45*time.Second {
		return errors.New("document dispatcher is not running")
	}
	return nil
}

func (dispatcher *DocumentIngestionDispatcher) Close() {
	dispatcher.mu.Lock()
	dispatcher.closed = true
	dispatcher.running.Store(false)
	if dispatcher.cancel != nil {
		dispatcher.cancel()
	}
	dispatcher.mu.Unlock()
	dispatcher.workers.Wait()
}

func (dispatcher *DocumentIngestionDispatcher) loop(ctx context.Context, operation string, interval time.Duration, tick *atomic.Int64, run func(context.Context) error) {
	defer dispatcher.workers.Done()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		iteration, cancel := context.WithTimeout(ctx, 12*time.Second)
		err := run(iteration)
		cancel()
		tick.Store(dispatcher.now().UnixNano())
		if err != nil && ctx.Err() == nil {
			var databaseError interface{ SQLState() string }
			sqlState := ""
			if errors.As(err, &databaseError) {
				sqlState = databaseError.SQLState()
			}
			dispatcher.logger.WarnContext(ctx, "document delivery or reconciliation will retry", "operation", operation, "task_queue", dispatcher.queue, "error_type", fmt.Sprintf("%T", err), "error_code", serviceerror.ToStatus(err).Code().String(), "sql_state", sqlState)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func IngestionWorkflowID(job document.DocumentJob, split ...bool) string {
	if job.AIAttempt > 0 {
		return fmt.Sprintf("document-ai-v1/%s/%s/%d/%d", job.AccountID, job.DocumentID, job.Generation, job.AIAttempt)
	}
	if len(split) > 0 && split[0] {
		return fmt.Sprintf("document-ingestion-v2/%s/%s/%d", job.AccountID, job.DocumentID, job.Generation)
	}
	return fmt.Sprintf("document-ingestion-v1/%s/%s/%d", job.AccountID, job.DocumentID, job.Generation)
}

func ingestionRequest(job document.DocumentJob, unlimited ...bool) documentworkflows.DocumentIngestionRequest {
	return documentworkflows.DocumentIngestionRequest{AIAttempt: job.AIAttempt, UnlimitedInference: len(unlimited) > 0 && unlimited[0], AccountID: job.AccountID, DocumentID: job.DocumentID, Generation: job.Generation}
}

func (dispatcher *DocumentIngestionDispatcher) dispatch(ctx context.Context) error {
	if dispatcher.retention != nil {
		if err := dispatcher.retention(ctx); err != nil {
			return err
		}
	}
	leases, err := dispatcher.service.Claim(ctx, 1, 30*time.Second, dispatcher.queue)
	if err != nil {
		return err
	}
	var wait sync.WaitGroup
	failures := make(chan error, len(leases))
	for _, lease := range leases {
		wait.Go(func() {
			if err := dispatcher.deliver(ctx, lease); err != nil {
				failures <- err
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

func (dispatcher *DocumentIngestionDispatcher) deliver(ctx context.Context, lease document.DocumentOutboxLease) error {
	if !validIngestionRequest(ingestionRequest(lease.Job)) {
		return dispatcher.service.Fail(ctx, lease.Job, "processing_failed")
	}
	if !dispatcher.now().Before(lease.DeliveryDeadline) {
		return dispatcher.service.FailExpired(ctx, lease.Job, "delivery_timeout")
	}
	workflowID := IngestionWorkflowID(lease.Job, lease.SplitPipeline)
	if lease.WorkflowID != workflowID || lease.TaskQueue == "" || !dispatcher.now().Before(lease.PermitEnd) {
		return dispatcher.service.Release(ctx, lease, dispatcher.now().Add(5*time.Second))
	}
	executionTimeout := 15 * time.Minute
	if lease.UnlimitedInference {
		executionTimeout = 0
	}
	operation, cancel := context.WithDeadline(ctx, lease.PermitEnd)
	run, err := dispatcher.client.ExecuteWorkflow(operation, client.StartWorkflowOptions{
		ID: workflowID, TaskQueue: lease.TaskQueue,
		WorkflowExecutionTimeout:                 executionTimeout,
		WorkflowIDReusePolicy:                    enumspb.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE,
		WorkflowIDConflictPolicy:                 enumspb.WORKFLOW_ID_CONFLICT_POLICY_FAIL,
		WorkflowExecutionErrorWhenAlreadyStarted: true,
	}, ingestionWorkflowName(lease.Job, lease.SplitPipeline), ingestionRequest(lease.Job, lease.UnlimitedInference))
	cancel()
	runID := ""
	if err == nil && run != nil {
		runID = run.GetRunID()
		if run.GetID() != workflowID || runID == "" {
			err = errors.New("unexpected ingestion workflow identity")
		}
	} else if err == nil {
		err = errors.New("missing ingestion workflow execution")
	}
	var duplicate *serviceerror.WorkflowExecutionAlreadyStarted
	if errors.As(err, &duplicate) {
		operation, cancel = context.WithTimeout(ctx, 4*time.Second)
		response, verifyErr := dispatcher.matchExecutionForQueue(operation, lease.Job, duplicate.RunId, true, lease.TaskQueue, lease.UnlimitedInference, lease.SplitPipeline)
		cancel()
		if verifyErr == nil {
			runID = response.GetWorkflowExecutionInfo().GetExecution().GetRunId()
			err = nil
		} else {
			err = verifyErr
		}
	}
	if err != nil {
		if releaseErr := dispatcher.service.Release(ctx, lease, dispatcher.now().Add(5*time.Second)); releaseErr != nil {
			return releaseErr
		}
		return err
	}
	return dispatcher.service.Acknowledge(ctx, lease, workflowID, runID)
}

func (dispatcher *DocumentIngestionDispatcher) matchExecution(ctx context.Context, job document.DocumentJob, runID string, verifyInput bool) (*workflowservice.DescribeWorkflowExecutionResponse, error) {
	return dispatcher.matchExecutionForQueue(ctx, job, runID, verifyInput, dispatcher.queue)
}

func (dispatcher *DocumentIngestionDispatcher) matchExecutionForQueue(ctx context.Context, job document.DocumentJob, runID string, verifyInput bool, queue string, unlimited ...bool) (*workflowservice.DescribeWorkflowExecutionResponse, error) {
	split := len(unlimited) > 1 && unlimited[1]
	workflowID := IngestionWorkflowID(job, split)
	response, err := dispatcher.client.DescribeWorkflowExecution(ctx, workflowID, runID)
	if err != nil {
		return nil, err
	}
	info := response.GetWorkflowExecutionInfo()
	if info.GetExecution().GetWorkflowId() != workflowID || info.GetExecution().GetRunId() == "" || (runID != "" && info.GetExecution().GetRunId() != runID) || info.GetType().GetName() != ingestionWorkflowName(job, split) || (queue != "" && info.GetTaskQueue() != queue) {
		return nil, errors.New("ingestion workflow ownership does not match")
	}
	if !verifyInput {
		return response, nil
	}
	history := dispatcher.client.GetWorkflowHistory(ctx, workflowID, info.GetExecution().GetRunId(), false, enumspb.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)
	if !history.HasNext() {
		return nil, errors.New("ingestion workflow start is unavailable")
	}
	event, err := history.Next()
	if err != nil {
		return nil, err
	}
	started := event.GetWorkflowExecutionStartedEventAttributes()
	expected, err := converter.GetDefaultDataConverter().ToPayloads(ingestionRequest(job, unlimited...))
	if err != nil {
		return nil, errors.New("encode ingestion identity")
	}
	actual := started.GetInput().GetPayloads()
	if started.GetWorkflowType().GetName() != ingestionWorkflowName(job, split) || started.GetTaskQueue().GetName() != info.GetTaskQueue() || len(actual) != 1 || !bytes.Equal(actual[0].GetData(), expected.Payloads[0].GetData()) || !bytes.Equal(actual[0].GetMetadata()["encoding"], expected.Payloads[0].GetMetadata()["encoding"]) {
		return nil, errors.New("ingestion workflow input does not match")
	}
	return response, nil
}

func (dispatcher *DocumentIngestionDispatcher) reconcile(ctx context.Context) error {
	cleanup, cancel := context.WithTimeout(ctx, 3*time.Second)
	cleanupErr := dispatcher.service.ReapUploads(cleanup)
	cancel()
	jobs, err := dispatcher.service.Pending(ctx, 20)
	if err != nil {
		return err
	}
	var wait sync.WaitGroup
	admission := make(chan struct{}, 4)
	failures := make(chan error, len(jobs))
	for _, pending := range jobs {
		select {
		case admission <- struct{}{}:
		case <-ctx.Done():
			wait.Wait()
			return ctx.Err()
		}
		wait.Go(func() {
			defer func() { <-admission }()
			if err := dispatcher.reconcileJob(ctx, pending); err != nil {
				failures <- err
			}
		})
	}
	wait.Wait()
	close(failures)
	for err := range failures {
		return err
	}
	return cleanupErr
}

func (dispatcher *DocumentIngestionDispatcher) reconcileJob(ctx context.Context, pending document.DocumentPendingJob) error {
	if pending.WorkflowID != IngestionWorkflowID(pending.Job, pending.SplitPipeline) {
		return errors.New("persisted ingestion workflow identity does not match")
	}
	if pending.TaskQueue == "" && !pending.Legacy {
		return errors.New("persisted ingestion task queue is missing")
	}
	operation, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	response, err := dispatcher.matchExecutionForQueue(operation, pending.Job, pending.RunID, pending.RunID == "" || pending.TaskQueue == "", pending.TaskQueue, pending.UnlimitedInference, pending.SplitPipeline)
	if err != nil {
		var missing *serviceerror.NotFound
		if errors.As(err, &missing) {
			return dispatcher.service.ResolveExecution(ctx, pending, "", "processing_timeout", true)
		}
		return err
	}
	info := response.GetWorkflowExecutionInfo()
	pending.TaskQueue = info.GetTaskQueue()
	if pending.UnlimitedInference && info.GetStatus() == enumspb.WORKFLOW_EXECUTION_STATUS_RUNNING && (pending.State == "superseded" || pending.State == "failed" || pending.State == "cancelled") {
		return dispatcher.client.CancelWorkflow(ctx, pending.WorkflowID, info.GetExecution().GetRunId())
	}
	code := ""
	switch info.GetStatus() {
	case enumspb.WORKFLOW_EXECUTION_STATUS_COMPLETED:
		code = "processing_incomplete"
	case enumspb.WORKFLOW_EXECUTION_STATUS_FAILED:
		code = "processing_failed"
	case enumspb.WORKFLOW_EXECUTION_STATUS_CANCELED:
		code = "processing_cancelled"
	case enumspb.WORKFLOW_EXECUTION_STATUS_TERMINATED:
		code = "processing_terminated"
	case enumspb.WORKFLOW_EXECUTION_STATUS_TIMED_OUT:
		code = "processing_timeout"
	}
	return dispatcher.service.ResolveExecution(ctx, pending, info.GetExecution().GetRunId(), code, false)
}

func ingestionWorkflowName(job document.DocumentJob, split bool) string {
	if job.AIAttempt > 0 {
		return documentworkflows.DocumentAIWorkflowName
	}
	if split {
		return documentworkflows.DocumentSearchableWorkflowName
	}
	return documentworkflows.DocumentIngestionWorkflowName
}
