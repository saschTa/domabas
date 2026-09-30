package repos

import (
	"context"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentImportSource interface {
	ImportConsent(context.Context, m.DocumentImportAuthority) (int64, error)
	ImportAcceptanceFacts(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation) (m.DocumentImportAcceptanceFacts, error)
	ReserveImport(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation) (m.DocumentUploadReservation, error)
	StageImport(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation, m.DocumentFileReference) error
	AcceptImport(context.Context, m.DocumentImportAuthority, m.DocumentUploadReservation, m.DocumentImportAcceptanceCommand) (m.DocumentImportResult, error)
	ImportReference(context.Context, m.DocumentImportAuthority) (m.DocumentFileReference, error)
	EmailLinks(context.Context, m.DocumentActor, string, int, string) (m.DocumentEmailLinks, error)
	EmailParents(context.Context, m.DocumentActor, string, int, string) (m.DocumentEmailParents, error)
}

type DocumentImportRepository struct{ source DocumentImportSource }

var _ p.DocumentImportRepository = (*DocumentImportRepository)(nil)

func NewDocumentImportRepository(source DocumentImportSource) *DocumentImportRepository {
	return &DocumentImportRepository{source}
}
func (r *DocumentImportRepository) ImportConsent(ctx context.Context, authority m.DocumentImportAuthority) (int64, error) {
	return r.source.ImportConsent(ctx, authority)
}
func (r *DocumentImportRepository) ReserveImport(ctx context.Context, a m.DocumentImportAuthority, input m.DocumentUploadReservation) (m.DocumentUploadReservation, error) {
	return r.source.ReserveImport(ctx, a, input)
}
func (r *DocumentImportRepository) StageImport(ctx context.Context, a m.DocumentImportAuthority, input m.DocumentUploadReservation, reference m.DocumentFileReference) error {
	return r.source.StageImport(ctx, a, input, reference)
}
func (r *DocumentImportRepository) ImportAcceptanceFacts(ctx context.Context, a m.DocumentImportAuthority, input m.DocumentUploadReservation) (m.DocumentImportAcceptanceFacts, error) {
	return r.source.ImportAcceptanceFacts(ctx, a, input)
}
func (r *DocumentImportRepository) AcceptImport(ctx context.Context, a m.DocumentImportAuthority, input m.DocumentUploadReservation, metadata m.DocumentImportAcceptanceCommand) (m.DocumentImportResult, error) {
	return r.source.AcceptImport(ctx, a, input, metadata)
}
func (r *DocumentImportRepository) ImportReference(ctx context.Context, a m.DocumentImportAuthority) (m.DocumentFileReference, error) {
	return r.source.ImportReference(ctx, a)
}
func (r *DocumentImportRepository) EmailLinks(ctx context.Context, a m.DocumentActor, id string, limit int, cursor string) (m.DocumentEmailLinks, error) {
	return r.source.EmailLinks(ctx, a, id, limit, cursor)
}
func (r *DocumentImportRepository) EmailParents(ctx context.Context, a m.DocumentActor, id string, limit int, cursor string) (m.DocumentEmailParents, error) {
	return r.source.EmailParents(ctx, a, id, limit, cursor)
}
