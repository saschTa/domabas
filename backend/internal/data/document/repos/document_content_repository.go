package repos

import (
	"context"
	"errors"
	"io"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	ports "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentContentSource interface {
	StoreUnlocked(context.Context, records.DocumentContentReference, []byte) (records.DocumentContentReference, error)
	Stage(context.Context, records.DocumentContentReference, string, io.Reader) (records.DocumentContentReference, error)
	Open(context.Context, records.DocumentContentReference) (io.ReadCloser, error)
	Remove(context.Context, records.DocumentContentReference) error
	Ready(context.Context) error
}
type DocumentContentRepository struct{ source DocumentContentSource }

var _ ports.DocumentContentStore = (*DocumentContentRepository)(nil)

func NewDocumentContentRepository(source DocumentContentSource) *DocumentContentRepository {
	return &DocumentContentRepository{source: source}
}

func adapterError(err error) error {
	if err == nil {
		return nil
	}
	var failure records.DocumentProcessorError
	if !errors.As(err, &failure) {
		return err
	}
	switch failure.Code {
	case "invalid_pdf_password":
		return domain.ErrInvalidPDFPassword
	case "too_large":
		return domain.ErrTooLarge
	case "unsupported_media":
		return domain.ErrUnsupportedMedia
	case "overloaded":
		return domain.ErrOverloaded
	case "context_length":
		return domain.ErrEmbeddingContextLength
	case "storage_unavailable", "inference_unavailable":
		return domain.DocumentProcessingError{Code: failure.Code, Retryable: true}
	case "invalid_invoice", "configuration_unavailable", "invalid_file", "encrypted_pdf", "resource_limit", "no_text", "processing_failed", "processing_timeout":
		return domain.DocumentProcessingError{Code: failure.Code}
	default:
		return domain.ErrUnavailable
	}
}
func (store *DocumentContentRepository) Stage(ctx context.Context, reservation domain.DocumentUploadReservation, filename string, reader io.Reader) (domain.DocumentFileReference, error) {
	ref, err := store.source.Stage(ctx, records.DocumentContentReference{AccountID: reservation.AccountID, UploaderID: reservation.UploaderID, DocumentID: reservation.ID, Location: "staged"}, filename, reader)
	return documentContentRecordToDomainMapper(ref), adapterError(err)
}
func (store *DocumentContentRepository) Open(ctx context.Context, ref domain.DocumentFileReference) (io.ReadCloser, error) {
	stream, err := store.source.Open(ctx, documentContentDomainToRecordMapper(ref))
	return stream, adapterError(err)
}
func (store *DocumentContentRepository) Remove(ctx context.Context, ref domain.DocumentFileReference) error {
	return adapterError(store.source.Remove(ctx, documentContentDomainToRecordMapper(ref)))
}
func (store *DocumentContentRepository) Ready(ctx context.Context) error {
	return adapterError(store.source.Ready(ctx))
}

func (store *DocumentContentRepository) StoreUnlocked(ctx context.Context, ref domain.DocumentFileReference, data []byte) (domain.DocumentFileReference, error) {
	value, err := store.source.StoreUnlocked(ctx, documentContentDomainToRecordMapper(ref), data)
	return documentContentRecordToDomainMapper(value), adapterError(err)
}
