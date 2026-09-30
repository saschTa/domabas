package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentInitializationRepository interface {
	InitializationFacts(context.Context) (m.DocumentInitializationFacts, error)
	InitializationDrift(context.Context, string) (bool, error)
	InitializeConfiguration(context.Context, m.DocumentInitializationCommand) error
}
