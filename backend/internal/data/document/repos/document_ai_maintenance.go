package repos

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentAIMaintenanceSource interface {
	AIMaintenanceFacts(context.Context) (m.DocumentAIMaintenanceFacts, error)
	MaintainAI(context.Context, m.DocumentAIMaintenanceCommand) error
}

func (r *DocumentIngestionRepository) AIMaintenanceFacts(ctx context.Context) (m.DocumentAIMaintenanceFacts, error) {
	return r.source.AIMaintenanceFacts(ctx)
}
func (r *DocumentIngestionRepository) MaintainAI(ctx context.Context, command m.DocumentAIMaintenanceCommand) error {
	return r.source.MaintainAI(ctx, command)
}
