package datasources

import (
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (s *DocumentDataSource) scheduledConfigurationRecordMapper(configuration m.DocumentProcessingConfiguration) r.DocumentConfigurationRecord {
	record := configurationRecord(configuration)
	return record
}
