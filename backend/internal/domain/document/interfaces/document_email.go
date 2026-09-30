package interfaces

import (
	"context"
	"io"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentImportRepository interface {
	ImportConsent(context.Context, m.DocumentImportAuthority) (int64, error)
	ImportAcceptanceFacts(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation) (m.DocumentImportAcceptanceFacts, error)
	ReserveImport(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation) (m.DocumentUploadReservation, error)
	StageImport(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation, m.DocumentFileReference) error
	AcceptImport(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation, m.DocumentImportAcceptanceCommand) (m.DocumentImportResult, error)
	ImportReference(context.Context, m.DocumentImportAuthority) (m.DocumentFileReference, error)
	EmailLinks(context.Context, m.DocumentActor, string, int, string) (m.DocumentEmailLinks, error)
	EmailParents(context.Context, m.DocumentActor, string, int, string) (m.DocumentEmailParents, error)
}
type DocumentEmailInspector interface {
	Inspect(context.Context, io.Reader, func(m.DocumentEmailPart) error) (m.DocumentEmailInspection, error)
	Envelope(io.Reader) (m.DocumentMetadata, error)
}
