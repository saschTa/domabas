package repos

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentReindexSource interface {
	ReindexMaintenanceFacts(context.Context) (m.DocumentReindexMaintenanceFacts, error)
	MaintainProcessing(context.Context, m.DocumentReindexMaintenanceCommand) error
	ReindexScheduleFacts(context.Context) ([]m.DocumentReindexScheduleFacts, error)
}

func (r *DocumentIngestionRepository) ReindexMaintenanceFacts(ctx context.Context) (m.DocumentReindexMaintenanceFacts, error) {
	return r.source.ReindexMaintenanceFacts(ctx)
}
func (r *DocumentIngestionRepository) MaintainProcessing(ctx context.Context, c m.DocumentReindexMaintenanceCommand) error {
	return r.source.MaintainProcessing(ctx, c)
}
func (r *DocumentIngestionRepository) ReindexScheduleFacts(ctx context.Context) ([]m.DocumentReindexScheduleFacts, error) {
	return r.source.ReindexScheduleFacts(ctx)
}
