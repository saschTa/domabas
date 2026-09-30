package interfaces

import (
	"context"

	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentRepository interface {
	Create(context.Context, string, documentmodels.Document) (documentmodels.Document, error)
	Get(context.Context, string, string) (documentmodels.Document, error)
	List(context.Context, string, documentmodels.DocumentPageRequest) (documentmodels.DocumentPage, error)
}
