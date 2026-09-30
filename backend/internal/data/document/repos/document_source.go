package repos

import (
	"context"

	documentrecords "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
)

type DocumentSource interface {
	CreateDocument(context.Context, model.Documents) (documentrecords.DocumentRecord, error)
	GetDocument(context.Context, string, string) (documentrecords.DocumentRecord, error)
	ListDocuments(context.Context, string, int, int, string) (documentrecords.DocumentRecords, error)
}
