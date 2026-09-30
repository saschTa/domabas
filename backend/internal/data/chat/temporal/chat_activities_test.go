package temporal

import (
	"context"
	"errors"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	w "github.com/domabas/domabas/backend/internal/domain/chat/workflows"
	"go.temporal.io/sdk/temporal"
)

type chatExecutionStub struct {
	run  func(context.Context, string) error
	step func(context.Context, string, int) (bool, error)
	fail func(context.Context, string, string) error
}

func (s *chatExecutionStub) Run(ctx context.Context, id string) error { return s.run(ctx, id) }
func (s *chatExecutionStub) RunStep(ctx context.Context, id string, ordinal int) (bool, error) {
	return s.step(ctx, id, ordinal)
}
func (s *chatExecutionStub) Fail(ctx context.Context, id, code string) error {
	return s.fail(ctx, id, code)
}

func TestChatActivitySanitizesErrorsAndPreservesRetryability(t *testing.T) {
	for _, tc := range []struct {
		err      error
		code     string
		terminal bool
	}{{m.ChatProcessingError{Code: "provider_rejected", Retryable: true}, "provider_rejected", false}, {m.ChatProcessingError{Code: "invalid_response"}, "invalid_response", true}, {m.ErrForbidden, "access_revoked", true}, {m.ChatProcessingError{Code: "private-secret"}, "chat_failed", true}, {errors.New("private-secret"), "chat_failed", false}} {
		t.Run(tc.code, func(t *testing.T) {
			job, _ := chatDispatchFixture()
			a := NewChatActivities(&chatExecutionStub{run: func(context.Context, string) error { return tc.err }})
			defer a.Close()
			err := a.Run(t.Context(), w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID})
			var app *temporal.ApplicationError
			if !errors.As(err, &app) || app.Type() != tc.code || app.NonRetryable() != tc.terminal || app.Message() == "private-secret" {
				t.Fatalf("unexpected failure %v", err)
			}
		})
	}
}

func TestChatActivityCloseCancelsAndJoinsWork(t *testing.T) {
	job, _ := chatDispatchFixture()
	started, drained := make(chan struct{}), make(chan struct{})
	a := NewChatActivities(&chatExecutionStub{run: func(ctx context.Context, _ string) error {
		close(started)
		<-ctx.Done()
		close(drained)
		return ctx.Err()
	}})
	result := make(chan error, 1)
	go func() { result <- a.Run(t.Context(), w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID}) }()
	<-started
	a.Close()
	select {
	case <-drained:
	default:
		t.Fatal("work not joined")
	}
	var failure *temporal.ApplicationError
	if err := <-result; !errors.As(err, &failure) || failure.NonRetryable() {
		t.Fatalf("shutdown was not retryable: %v", err)
	}
}

func TestChatActivityRejectsInvalidIdentityBeforeService(t *testing.T) {
	a := NewChatActivities(&chatExecutionStub{run: func(context.Context, string) error { t.Fatal("invalid identity reached service"); return nil }})
	defer a.Close()
	err := a.Run(t.Context(), w.ChatTurnRequest{TurnID: "invalid", AccountID: "invalid"})
	var failure *temporal.ApplicationError
	if !errors.As(err, &failure) || !failure.NonRetryable() {
		t.Fatalf("invalid identity error=%v", err)
	}
}

func TestChatStepActivityPreservesOrdinalAndSanitizesFailures(t *testing.T) {
	job, _ := chatDispatchFixture()
	a := NewChatActivities(&chatExecutionStub{step: func(_ context.Context, id string, ordinal int) (bool, error) {
		if id != job.TurnID || ordinal != 7 {
			t.Fatalf("step identity changed: %s/%d", id, ordinal)
		}
		return false, m.ChatProcessingError{Code: "provider_unavailable", Retryable: true}
	}})
	defer a.Close()
	result, err := a.RunStep(t.Context(), w.ChatStepRequest{Request: w.ChatTurnRequest{TurnID: job.TurnID, AccountID: job.AccountID}, Ordinal: 7})
	var failure *temporal.ApplicationError
	if result.Completed || !errors.As(err, &failure) || failure.NonRetryable() || failure.Type() != "provider_unavailable" {
		t.Fatalf("step result=%+v error=%v", result, err)
	}
}
