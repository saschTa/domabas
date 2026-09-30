package repos

import (
	"bytes"
	"context"
	"errors"
	"image/jpeg"
	"io"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	ports "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentThumbnailProcessorSource interface {
	RenderThumbnail(context.Context, io.Reader, string) (records.DocumentThumbnailResult, error)
}

type DocumentThumbnailProcessorRepository struct {
	source DocumentThumbnailProcessorSource
}

var _ ports.DocumentThumbnailRenderer = (*DocumentThumbnailProcessorRepository)(nil)

func NewDocumentThumbnailProcessorRepository(source DocumentThumbnailProcessorSource) *DocumentThumbnailProcessorRepository {
	return &DocumentThumbnailProcessorRepository{source: source}
}

func (repository *DocumentThumbnailProcessorRepository) RenderThumbnail(ctx context.Context, reader io.Reader, mediaType string) (models.DocumentThumbnailImage, error) {
	result, err := repository.source.RenderThumbnail(ctx, reader, mediaType)
	if err != nil {
		var failure records.DocumentProcessorError
		if errors.As(err, &failure) && (failure.Code == "processing_failed" || failure.Code == "processing_timeout") {
			return models.DocumentThumbnailImage{}, models.DocumentProcessingError{Code: failure.Code, Retryable: true}
		}
		return models.DocumentThumbnailImage{}, adapterError(err)
	}
	if result.MediaType != "image/jpeg" || len(result.Bytes) < 1 || len(result.Bytes) > models.MaxThumbnailBytes || result.Width < 1 || result.Height < 1 || result.Width > models.MaxThumbnailWidth || result.Height > models.MaxThumbnailHeight {
		return models.DocumentThumbnailImage{}, models.DocumentProcessingError{Code: "processing_failed", Retryable: true}
	}
	configuration, err := jpeg.DecodeConfig(bytes.NewReader(result.Bytes))
	if err != nil || configuration.Width != result.Width || configuration.Height != result.Height {
		return models.DocumentThumbnailImage{}, models.DocumentProcessingError{Code: "processing_failed", Retryable: true}
	}
	if _, err = jpeg.Decode(bytes.NewReader(result.Bytes)); err != nil {
		return models.DocumentThumbnailImage{}, models.DocumentProcessingError{Code: "processing_failed", Retryable: true}
	}
	return documentThumbnailResultToDomainMapper(result), nil
}
