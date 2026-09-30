package temporal

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	emailworkflows "github.com/domabas/domabas/backend/internal/domain/email/workflows"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
)

type EmailDispatchService interface {
	Schedule(context.Context) error
	ClaimDelivery(context.Context, string) (*m.EmailExecution, error)
	AcknowledgeDelivery(context.Context, m.EmailExecution, string) error
	PendingExecutions(context.Context) ([]m.EmailExecution, error)
	ResolveExecution(context.Context, m.EmailExecution, string, string, bool) error
	Cleanup(context.Context) error
}

type EmailCredentialRotationService interface{ Rotate(context.Context) error }

type EmailPollDispatcher struct {
	service         EmailDispatchService
	rotation        EmailCredentialRotationService
	client          EmailTemporalClient
	queue           string
	logger          *slog.Logger
	retention       func(context.Context) error
	mutex           sync.Mutex
	cancel          context.CancelFunc
	started, closed bool
	active          sync.WaitGroup
	running         atomic.Bool
	tick            atomic.Int64
	now             func() time.Time
}

func NewEmailPollDispatcher(service EmailDispatchService, rotation EmailCredentialRotationService, client EmailTemporalClient, queue string, logger *slog.Logger, retention func(context.Context) error) *EmailPollDispatcher {
	return &EmailPollDispatcher{service: service, rotation: rotation, client: client, queue: queue, logger: logger, retention: retention, now: time.Now}
}

func (d *EmailPollDispatcher) Start() error {
	d.mutex.Lock()
	defer d.mutex.Unlock()
	if d.started || d.closed || d.service == nil || d.client == nil || d.retention == nil || d.queue == "" {
		return errors.New("email dispatcher cannot start")
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

func (d *EmailPollDispatcher) Close() {
	d.mutex.Lock()
	d.closed = true
	d.running.Store(false)
	if d.cancel != nil {
		d.cancel()
	}
	d.mutex.Unlock()
	d.active.Wait()
}

func (d *EmailPollDispatcher) Ping() error {
	if !d.running.Load() || d.now().Sub(time.Unix(0, d.tick.Load())) > 45*time.Second {
		return errors.New("email dispatcher unavailable")
	}
	return nil
}

func (d *EmailPollDispatcher) loop(ctx context.Context) {
	defer d.active.Done()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	nextMaintenance := time.Time{}
	for {
		operation, cancel := context.WithTimeout(ctx, 20*time.Second)
		err := d.cycle(operation)
		if !d.now().Before(nextMaintenance) {
			err = errors.Join(err, d.service.Cleanup(operation), d.rotation.Rotate(operation))
			nextMaintenance = d.now().Add(time.Minute)
		}
		cancel()
		d.tick.Store(d.now().UnixNano())
		if err != nil && ctx.Err() == nil {
			d.logger.Warn("email dispatcher operation failed")
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (d *EmailPollDispatcher) cycle(ctx context.Context) error {
	if err := d.retention(ctx); err != nil {
		return err
	}
	if err := d.reconcile(ctx); err != nil {
		return err
	}
	if err := d.service.Schedule(ctx); err != nil {
		return err
	}
	execution, err := d.service.ClaimDelivery(ctx, d.queue)
	if err != nil || execution == nil {
		return err
	}
	return d.deliver(ctx, *execution)
}

func (d *EmailPollDispatcher) deliver(ctx context.Context, execution m.EmailExecution) error {
	if execution.WorkflowRunID != "" || execution.WorkflowID != "domabas-email-"+execution.RunID || execution.TaskQueue == "" || !d.now().Before(execution.LatestPermitEnd) || !d.now().Before(execution.StartWindowEnd) {
		return nil
	}
	operation, cancel := context.WithDeadline(ctx, execution.LatestPermitEnd)
	run, err := d.client.ExecuteWorkflow(operation, client.StartWorkflowOptions{ID: execution.WorkflowID, TaskQueue: execution.TaskQueue, WorkflowExecutionTimeout: 10 * time.Minute, WorkflowIDReusePolicy: enums.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE, WorkflowIDConflictPolicy: enums.WORKFLOW_ID_CONFLICT_POLICY_FAIL, WorkflowExecutionErrorWhenAlreadyStarted: true}, emailworkflows.EmailPollWorkflowName, emailworkflows.EmailPollWorkflowInput{RunID: execution.RunID})
	cancel()
	runID := ""
	if err == nil && run != nil && run.GetID() == execution.WorkflowID {
		runID = run.GetRunID()
	}
	var duplicate *serviceerror.WorkflowExecutionAlreadyStarted
	if errors.As(err, &duplicate) {
		response, verifyErr := verifyExecution(ctx, d.client, execution.RunID, duplicate.RunId, execution.TaskQueue)
		if verifyErr != nil {
			return verifyErr
		}
		runID = response.GetWorkflowExecutionInfo().GetExecution().GetRunId()
		err = nil
	}
	if err != nil {
		return err
	}
	if runID == "" {
		return errors.New("email workflow start returned no execution")
	}
	return d.service.AcknowledgeDelivery(ctx, execution, runID)
}

func (d *EmailPollDispatcher) reconcile(ctx context.Context) error {
	executions, err := d.service.PendingExecutions(ctx)
	if err != nil {
		return err
	}
	for _, execution := range executions {
		verify := verifyExecution
		if execution.WorkflowRunID != "" {
			verify = describeExecution
		}
		response, err := verify(ctx, d.client, execution.RunID, execution.WorkflowRunID, execution.TaskQueue)
		var missing *serviceerror.NotFound
		if errors.As(err, &missing) {
			if err = d.service.ResolveExecution(ctx, execution, execution.WorkflowRunID, "delivery_timeout", true); err != nil {
				return err
			}
			continue
		}
		if err != nil {
			continue
		}
		info := response.GetWorkflowExecutionInfo()
		run := info.GetExecution().GetRunId()
		if info.GetStatus() == enums.WORKFLOW_EXECUTION_STATUS_RUNNING {
			if execution.WorkflowRunID == "" {
				if err = d.service.AcknowledgeDelivery(ctx, execution, run); err != nil {
					return err
				}
			}
			continue
		}
		code := ""
		if info.GetStatus() != enums.WORKFLOW_EXECUTION_STATUS_COMPLETED {
			code = "processing_failed"
		}
		if err = d.service.ResolveExecution(ctx, execution, run, code, false); err != nil {
			return err
		}
	}
	return nil
}
