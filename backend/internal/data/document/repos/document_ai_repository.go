package repos

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"time"
)

type DocumentAISource interface {
	AIClaim(ctx context.Context, limit int, lease time.Duration, policy m.DocumentDeliveryPolicy, queues ...string) ([]m.DocumentOutboxLease, error)
	AIPending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error)
	AIAcknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error
	AIRelease(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error
	AIExecutionFacts(context.Context, m.DocumentPendingJob) (m.DocumentExecutionFacts, error)
	AIResolveExecution(ctx context.Context, p m.DocumentPendingJob, command m.DocumentExecutionResolution) error
	AIFail(ctx context.Context, j m.DocumentJob, code string) error
	AICompletionFacts(context.Context, m.DocumentJob) (m.DocumentAICompletionFacts, error)
	AIComplete(ctx context.Context, j m.DocumentJob, facts m.DocumentAICompletionFacts) error
}
type DocumentAIRepository struct{ source DocumentAISource }

func NewDocumentAIRepository(source DocumentAISource) *DocumentAIRepository {
	return &DocumentAIRepository{source}
}
func (r *DocumentAIRepository) Claim(ctx context.Context, limit int, lease time.Duration, policy m.DocumentDeliveryPolicy, queues ...string) ([]m.DocumentOutboxLease, error) {
	return r.source.AIClaim(ctx, limit, lease, policy, queues...)
}
func (r *DocumentAIRepository) Pending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error) {
	return r.source.AIPending(ctx, limit)
}
func (r *DocumentAIRepository) Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error {
	return r.source.AIAcknowledge(ctx, l, workflow, run)
}
func (r *DocumentAIRepository) Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error {
	return r.source.AIRelease(ctx, l, next)
}
func (r *DocumentAIRepository) ExecutionFacts(ctx context.Context, pending m.DocumentPendingJob) (m.DocumentExecutionFacts, error) {
	return r.source.AIExecutionFacts(ctx, pending)
}
func (r *DocumentAIRepository) ResolveExecution(ctx context.Context, p m.DocumentPendingJob, command m.DocumentExecutionResolution) error {
	return r.source.AIResolveExecution(ctx, p, command)
}
func (r *DocumentAIRepository) Fail(ctx context.Context, j m.DocumentJob, code string) error {
	return r.source.AIFail(ctx, j, code)
}
func (r *DocumentAIRepository) CompletionFacts(ctx context.Context, j m.DocumentJob) (m.DocumentAICompletionFacts, error) {
	return r.source.AICompletionFacts(ctx, j)
}
func (r *DocumentAIRepository) Complete(ctx context.Context, j m.DocumentJob, facts m.DocumentAICompletionFacts) error {
	return r.source.AIComplete(ctx, j, facts)
}
