package repos

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (rp *DocumentIngestionRepository) OCR(ctx context.Context, a m.DocumentActor, id string) (m.DocumentOCR, error) {
	record, err := rp.source.OCRRecord(ctx, a, id)
	return m.DocumentOCR(record), err
}
func (rp *DocumentIngestionRepository) CorrectionFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentCorrectionFacts, error) {
	return rp.source.CorrectionFacts(ctx, a, id)
}
func (rp *DocumentIngestionRepository) CorrectOCR(ctx context.Context, a m.DocumentActor, id string, input m.DocumentCorrectionCommand) (m.DocumentOCR, error) {
	record, err := rp.source.CorrectOCRRecord(ctx, a, id, input)
	return m.DocumentOCR(record), err
}
func (rp *DocumentIngestionRepository) Delete(ctx context.Context, a m.DocumentActor, id string) error {
	return rp.source.Delete(ctx, a, id)
}
func (rp *DocumentIngestionRepository) ReapDeleted(ctx context.Context, limit int) ([]m.DocumentCleanupLease, error) {
	records, err := rp.source.ReapDeletedRecords(ctx, limit)
	values := make([]m.DocumentCleanupLease, 0, len(records))
	for _, record := range records {
		values = append(values, m.DocumentCleanupLease(record))
	}
	return values, err
}
func (rp *DocumentIngestionRepository) DeletedReaped(ctx context.Context, lease m.DocumentCleanupLease, command m.DocumentCleanupCompletion) error {
	return rp.source.DeletedReaped(ctx, lease, command)
}
