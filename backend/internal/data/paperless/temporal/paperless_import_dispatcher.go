package temporal

import (
	"context"
	"errors"
	"sync"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	paperlessworkflows "github.com/domabas/domabas/backend/internal/domain/paperless/workflows"
	enums "go.temporal.io/api/enums/v1"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
)

type PaperlessDispatchJobs interface {
	Next(context.Context) (*m.PaperlessExecution, error)
	Fail(context.Context, string, string) error
	Closed(context.Context, string) error
}

type PaperlessImportDispatcher struct {
	jobs        PaperlessDispatchJobs
	client      client.Client
	ctx         context.Context
	cancel      context.CancelFunc
	done        chan struct{}
	mu          sync.Mutex
	lastSuccess time.Time
	started     bool
	closed      bool
}

func NewPaperlessImportDispatcher(jobs PaperlessDispatchJobs, remote client.Client) *PaperlessImportDispatcher {
	ctx, cancel := context.WithCancel(context.Background())
	return &PaperlessImportDispatcher{jobs: jobs, client: remote, ctx: ctx, cancel: cancel, done: make(chan struct{})}
}

func (d *PaperlessImportDispatcher) Start(startup context.Context) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.started || d.closed {
		return errors.New("Paperless dispatcher cannot start")
	}
	probe, cancel := context.WithTimeout(startup, 10*time.Second)
	err := d.tick(probe)
	cancel()
	if err != nil {
		return err
	}
	d.started = true
	d.lastSuccess = time.Now()
	go func() {
		defer close(d.done)
		timer := time.NewTicker(2 * time.Second)
		defer timer.Stop()
		for {
			ctx, cancel := context.WithTimeout(d.ctx, 10*time.Second)
			err := d.tick(ctx)
			cancel()
			if err == nil {
				d.mu.Lock()
				d.lastSuccess = time.Now()
				d.mu.Unlock()
			}
			select {
			case <-d.ctx.Done():
				return
			case <-timer.C:
			}
		}
	}()
	return nil
}

func (d *PaperlessImportDispatcher) Ping() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.started || d.closed || time.Since(d.lastSuccess) > 30*time.Second {
		return errors.New("Paperless dispatcher is unavailable")
	}
	return nil
}

func (d *PaperlessImportDispatcher) Close() {
	d.mu.Lock()
	d.closed = true
	d.cancel()
	started := d.started
	d.mu.Unlock()
	if started {
		<-d.done
	}
}

func (d *PaperlessImportDispatcher) tick(ctx context.Context) error {
	e, err := d.jobs.Next(ctx)
	if err != nil || e == nil {
		return err
	}
	id := "domabas-paperless-" + e.ID
	info, err := d.client.DescribeWorkflowExecution(ctx, id, "")
	if err == nil {
		execution := info.GetWorkflowExecutionInfo()
		if execution.GetTaskQueue() != e.TaskQueue || execution.GetType().GetName() != paperlessworkflows.PaperlessImportWorkflowName {
			return errors.New("Paperless execution ownership mismatch")
		}
		if execution.GetStatus() == enums.WORKFLOW_EXECUTION_STATUS_RUNNING {
			return nil
		}
		if err := d.jobs.Fail(ctx, e.ID, "workflow_closed"); err != nil {
			return err
		}
		if execution.GetStatus() != enums.WORKFLOW_EXECUTION_STATUS_COMPLETED && (execution.GetCloseTime() == nil || time.Since(execution.GetCloseTime().AsTime()) < 90*time.Second) {
			return nil
		}
		return d.jobs.Closed(ctx, e.ID)
	}
	var missing *serviceerror.NotFound
	if !errors.As(err, &missing) {
		return err
	}
	if time.Since(e.FirstStart) > 20*time.Hour {
		if err := d.jobs.Fail(ctx, e.ID, "delivery_expired"); err != nil {
			return err
		}
		return d.jobs.Closed(ctx, e.ID)
	}
	_, err = d.client.ExecuteWorkflow(ctx, client.StartWorkflowOptions{ID: id, TaskQueue: e.TaskQueue, WorkflowExecutionTimeout: 7 * 24 * time.Hour, WorkflowIDReusePolicy: enums.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE}, paperlessworkflows.PaperlessImportWorkflowName, e.ID)
	var exists *serviceerror.WorkflowExecutionAlreadyStarted
	if errors.As(err, &exists) {
		return nil
	}
	return err
}
