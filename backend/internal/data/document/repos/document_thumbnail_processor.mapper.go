package repos

import (
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentThumbnailResultToDomainMapper(result records.DocumentThumbnailResult) models.DocumentThumbnailImage {
	return models.DocumentThumbnailImage{Bytes: result.Bytes, Width: result.Width, Height: result.Height, MediaType: result.MediaType}
}
