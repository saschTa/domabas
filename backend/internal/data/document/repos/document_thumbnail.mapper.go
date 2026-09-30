package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentThumbnailJobsMapper(records []r.DocumentThumbnailJobRecord) []m.DocumentThumbnailJob {
	result := make([]m.DocumentThumbnailJob, len(records))
	for i, record := range records {
		result[i] = m.DocumentThumbnailJob(record)
	}
	return result
}
