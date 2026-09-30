package temporal

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	w "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"sync"
	"time"
)

type DocumentThumbnailActivityService interface {
	Render(context.Context, m.DocumentThumbnailJob) error
	Finish(context.Context, m.DocumentThumbnailJob, m.DocumentThumbnailOutcome) error
}
type DocumentThumbnailActivities struct {
	service  DocumentThumbnailActivityService
	mu       sync.Mutex
	closing  bool
	active   sync.WaitGroup
	lifetime context.Context
	cancel   context.CancelFunc
}

func NewDocumentThumbnailActivities(service DocumentThumbnailActivityService) *DocumentThumbnailActivities {
	ctx, cancel := context.WithCancel(context.Background())
	return &DocumentThumbnailActivities{service: service, lifetime: ctx, cancel: cancel}
}
func (a *DocumentThumbnailActivities) Close() {
	a.mu.Lock()
	a.closing = true
	a.cancel()
	a.mu.Unlock()
	a.active.Wait()
}
func (a *DocumentThumbnailActivities) enter(ctx context.Context) (context.Context, func(), error) {
	a.mu.Lock()
	if a.closing {
		a.mu.Unlock()
		return nil, nil, context.Canceled
	}
	a.active.Add(1)
	a.mu.Unlock()
	ctx, cancel := context.WithCancel(ctx)
	stop := context.AfterFunc(a.lifetime, cancel)
	return ctx, func() { stop(); cancel(); a.active.Done() }, nil
}
func (a *DocumentThumbnailActivities) Render(ctx context.Context, input w.DocumentThumbnailRequest) (w.DocumentThumbnailResult, error) {
	ctx, done, err := a.enter(ctx)
	if err != nil {
		return w.DocumentThumbnailResult{}, err
	}
	defer done()
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	finished := make(chan struct{})
	defer close(finished)
	activity.RecordHeartbeat(ctx)
	go func() {
		for {
			select {
			case <-ticker.C:
				activity.RecordHeartbeat(ctx)
			case <-finished:
				return
			case <-ctx.Done():
				return
			}
		}
	}()
	err = a.service.Render(ctx, thumbnailRequestJobMapper(input))
	if err == nil {
		return w.DocumentThumbnailResult{}, nil
	}
	outcome := m.DocumentThumbnailFailure(err)
	if !outcome.Retryable {
		return w.DocumentThumbnailResult{FailureCode: outcome.FailureCode}, nil
	}
	return w.DocumentThumbnailResult{}, temporal.NewApplicationError("thumbnail dependency unavailable", "ThumbnailUnavailable")
}
func (a *DocumentThumbnailActivities) Finish(ctx context.Context, input w.DocumentThumbnailFailure) error {
	ctx, done, err := a.enter(ctx)
	if err != nil {
		return err
	}
	defer done()
	return a.service.Finish(ctx, thumbnailRequestJobMapper(input.Request), m.DocumentThumbnailOutcome{FailureCode: input.Outcome.FailureCode, Retryable: input.Outcome.Retryable})
}
