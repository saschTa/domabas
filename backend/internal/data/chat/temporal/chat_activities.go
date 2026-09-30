package temporal

import (
	"context"
	"errors"
	"sync"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	chatworkflows "github.com/domabas/domabas/backend/internal/domain/chat/workflows"
	"github.com/google/uuid"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
)

type ChatExecutionService interface {
	Run(context.Context, string) error
	RunStep(context.Context, string, int) (bool, error)
	Fail(context.Context, string, string) error
}

type ChatActivities struct {
	service  ChatExecutionService
	mu       sync.Mutex
	closing  bool
	active   sync.WaitGroup
	lifetime context.Context
	cancel   context.CancelFunc
}

func NewChatActivities(service ChatExecutionService) *ChatActivities {
	lifetime, cancel := context.WithCancel(context.Background())
	return &ChatActivities{service: service, lifetime: lifetime, cancel: cancel}
}

func (a *ChatActivities) Close() {
	a.mu.Lock()
	a.closing = true
	a.cancel()
	a.mu.Unlock()
	a.active.Wait()
}

func (a *ChatActivities) Run(ctx context.Context, input chatworkflows.ChatTurnRequest) error {
	return a.invoke(ctx, input, func(ctx context.Context) error { return a.service.Run(ctx, input.TurnID) })
}

func (a *ChatActivities) RunStep(ctx context.Context, input chatworkflows.ChatStepRequest) (chatworkflows.ChatStepResult, error) {
	var result chatworkflows.ChatStepResult
	err := a.invoke(ctx, input.Request, func(ctx context.Context) error {
		var err error
		result.Completed, err = a.service.RunStep(ctx, input.Request.TurnID, input.Ordinal)
		return err
	})
	return result, err
}

func (a *ChatActivities) Fail(ctx context.Context, input chatworkflows.ChatTurnFailure) error {
	return a.invoke(ctx, input.Request, func(ctx context.Context) error {
		return a.service.Fail(ctx, input.Request.TurnID, chatworkflows.ChatFailureCode(input.Code))
	})
}

func (a *ChatActivities) invoke(ctx context.Context, input chatworkflows.ChatTurnRequest, call func(context.Context) error) error {
	if !validChatRequest(input) {
		return temporal.NewNonRetryableApplicationError("invalid chat identifiers", "chat_failed", nil)
	}
	a.mu.Lock()
	if a.closing {
		a.mu.Unlock()
		return temporal.NewApplicationError("chat worker is stopping", "provider_unavailable")
	}
	a.active.Add(1)
	a.mu.Unlock()
	defer a.active.Done()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stop := context.AfterFunc(a.lifetime, cancel)
	defer stop()
	if activity.IsActivity(ctx) {
		done := make(chan struct{})
		go func() {
			defer close(done)
			ticker := time.NewTicker(3 * time.Second)
			defer ticker.Stop()
			activity.RecordHeartbeat(ctx)
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					activity.RecordHeartbeat(ctx)
				}
			}
		}()
		defer func() { cancel(); <-done }()
	}
	err := call(ctx)
	if err == nil {
		return nil
	}
	if a.lifetime.Err() != nil {
		return temporal.NewApplicationError("chat worker is stopping", "provider_unavailable")
	}
	if errors.Is(err, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
		return temporal.NewCanceledError()
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return temporal.NewApplicationError("chat request timed out", "chat_timeout")
	}
	if errors.Is(err, m.ErrCancelled) {
		return temporal.NewCanceledError()
	}
	if errors.Is(err, m.ErrForbidden) || errors.Is(err, m.ErrUnauthorized) || errors.Is(err, m.ErrNotFound) {
		return temporal.NewNonRetryableApplicationError("chat access is no longer available", "access_revoked", nil)
	}
	var failure m.ChatProcessingError
	if errors.As(err, &failure) {
		code := chatworkflows.ChatFailureCode(failure.Code)
		if !failure.Retryable {
			return temporal.NewNonRetryableApplicationError("chat request failed", code, nil)
		}
		return temporal.NewApplicationError("chat provider is unavailable", code)
	}
	return temporal.NewApplicationError("chat request failed", "chat_failed")
}

func validChatRequest(input chatworkflows.ChatTurnRequest) bool {
	for _, value := range []string{input.TurnID, input.AccountID} {
		id, err := uuid.Parse(value)
		if err != nil || id == uuid.Nil || id.String() != value {
			return false
		}
	}
	return true
}
