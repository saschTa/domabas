package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"time"
)

type DocumentAIRepository interface {
	Claim(ctx context.Context, limit int, lease time.Duration, policy m.DocumentDeliveryPolicy, queues ...string) ([]m.DocumentOutboxLease, error)
	Pending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error)
	Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error
	Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error
	ExecutionFacts(context.Context, m.DocumentPendingJob) (m.DocumentExecutionFacts, error)
	ResolveExecution(ctx context.Context, p m.DocumentPendingJob, command m.DocumentExecutionResolution) error
	Fail(ctx context.Context, j m.DocumentJob, code string) error
	CompletionFacts(context.Context, m.DocumentJob) (m.DocumentAICompletionFacts, error)
	Complete(ctx context.Context, j m.DocumentJob, facts m.DocumentAICompletionFacts) error
}
