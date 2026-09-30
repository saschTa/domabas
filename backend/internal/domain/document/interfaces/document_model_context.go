package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentModelContextReader interface {
	ModelContext(context.Context, string) (m.DocumentModelContext, error)
}
