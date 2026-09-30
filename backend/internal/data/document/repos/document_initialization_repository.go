package repos

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentInitializationSource interface {
	InitializationFacts(context.Context) (m.DocumentInitializationFacts, error)
	InitializationDrift(context.Context, string) (bool, error)
	InitializeConfiguration(context.Context, m.DocumentInitializationCommand) error
}
type DocumentInitializationRepository struct{ source DocumentInitializationSource }

func NewDocumentInitializationRepository(source DocumentInitializationSource) *DocumentInitializationRepository {
	return &DocumentInitializationRepository{source: source}
}
func (r *DocumentInitializationRepository) InitializationFacts(ctx context.Context) (m.DocumentInitializationFacts, error) {
	return r.source.InitializationFacts(ctx)
}
func (r *DocumentInitializationRepository) InitializationDrift(ctx context.Context, fingerprint string) (bool, error) {
	return r.source.InitializationDrift(ctx, fingerprint)
}
func (r *DocumentInitializationRepository) InitializeConfiguration(ctx context.Context, command m.DocumentInitializationCommand) error {
	return r.source.InitializeConfiguration(ctx, command)
}
