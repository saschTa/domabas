package repos

import (
	documentrecords "github.com/domabas/domabas/backend/internal/data/document/models"
	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentRecordToDomainMapper(record documentrecords.DocumentRecord) documentmodels.Document {
	return documentIngestionRecordToDomainMapper(record)
}
