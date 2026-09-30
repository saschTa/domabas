package interfaces

import (
	"context"
	"io"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type PaperlessRepository interface {
	Preview(context.Context, m.PaperlessConnection, int) (m.PaperlessPage, error)
	Original(context.Context, m.PaperlessConnection, int64) (m.PaperlessOriginal, error)
}

type PaperlessDocumentImporter interface {
	ReserveUpload(context.Context, d.DocumentActor) (d.DocumentUploadReservation, error)
	StageUpload(context.Context, d.DocumentActor, d.DocumentUploadReservation, string, io.Reader) (d.DocumentFileReference, error)
	AcceptUpload(context.Context, d.DocumentActor, d.DocumentUploadReservation, d.DocumentMetadata) (d.Document, error)
	AbandonUpload(context.Context, d.DocumentActor, d.DocumentUploadReservation) error
}
