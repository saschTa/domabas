package temporal

import (
	"context"
	"sync"
	"time"

	paperlessworkflows "github.com/domabas/domabas/backend/internal/domain/paperless/workflows"
	"go.temporal.io/sdk/activity"
	sdk "go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

type PaperlessImportPipeline interface {
	Step(context.Context, string) (bool, error)
	Fail(context.Context, string, string) error
}

type PaperlessImportActivities struct {
	pipeline PaperlessImportPipeline
	mu       sync.Mutex
	closed   bool
	active   sync.WaitGroup
	lifetime context.Context
	cancel   context.CancelFunc
}

func NewPaperlessImportActivities(p PaperlessImportPipeline) *PaperlessImportActivities {
	ctx, cancel := context.WithCancel(context.Background())
	return &PaperlessImportActivities{pipeline: p, lifetime: ctx, cancel: cancel}
}

func (a *PaperlessImportActivities) Register(w worker.Registry) {
	w.RegisterWorkflowWithOptions(paperlessworkflows.PaperlessImportWorkflow, workflow.RegisterOptions{Name: paperlessworkflows.PaperlessImportWorkflowName})
	w.RegisterActivityWithOptions(a.Step, activity.RegisterOptions{Name: paperlessworkflows.PaperlessStepActivityName})
	w.RegisterActivityWithOptions(a.Fail, activity.RegisterOptions{Name: paperlessworkflows.PaperlessFailActivityName})
}

func (a *PaperlessImportActivities) run(ctx context.Context, work func(context.Context) (bool, error)) (bool, error) {
	a.mu.Lock()
	if a.closed {
		a.mu.Unlock()
		return false, context.Canceled
	}
	a.active.Add(1)
	a.mu.Unlock()
	defer a.active.Done()
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	stop := context.AfterFunc(a.lifetime, cancel)
	defer stop()
	done, err := work(ctx)
	if err != nil {
		return false, sdk.NewApplicationError("Paperless step temporarily unavailable", "PaperlessUnavailable")
	}
	return done, nil
}

func (a *PaperlessImportActivities) Step(ctx context.Context, id string) (bool, error) {
	return a.run(ctx, func(ctx context.Context) (bool, error) { return a.pipeline.Step(ctx, id) })
}

func (a *PaperlessImportActivities) Fail(ctx context.Context, id string) error {
	_, err := a.run(ctx, func(ctx context.Context) (bool, error) { return true, a.pipeline.Fail(ctx, id, "retry_exhausted") })
	return err
}

func (a *PaperlessImportActivities) Close() {
	a.mu.Lock()
	a.closed = true
	a.cancel()
	a.mu.Unlock()
	a.active.Wait()
}
