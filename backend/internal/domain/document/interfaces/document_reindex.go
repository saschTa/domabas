package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentReindexRepository interface {
	ReindexMaintenanceFacts(context.Context) (m.DocumentReindexMaintenanceFacts, error)
	MaintainProcessing(context.Context, m.DocumentReindexMaintenanceCommand) error
	ReindexScheduleFacts(context.Context) ([]m.DocumentReindexScheduleFacts, error)
}
