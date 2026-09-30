package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentAIMaintenanceRepository interface {
	AIMaintenanceFacts(context.Context) (m.DocumentAIMaintenanceFacts, error)
	MaintainAI(context.Context, m.DocumentAIMaintenanceCommand) error
}
