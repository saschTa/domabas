package services

import (
	"context"

	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentPropertyService struct {
	repository p.DocumentPropertyRepository
	extractor  p.DocumentPropertyExtractor
}

func NewDocumentPropertyService(repository p.DocumentPropertyRepository, extractor p.DocumentPropertyExtractor) *DocumentPropertyService {
	return &DocumentPropertyService{repository, extractor}
}

func (s *DocumentPropertyService) Enrich(ctx context.Context, job m.DocumentJob) error {
	work, err := s.repository.Work(ctx, job)
	if err != nil {
		return err
	}
	if !work.Eligible {
		return m.ErrStaleJob
	}
	if work.Stage == "embedding" || work.Stage == "finalizing" || work.Stage == "complete" {
		return nil
	}
	if work.Stage != "enriching" {
		return m.ErrStaleJob
	}
	work.NextStage = "embedding"
	if job.AIAttempt > 0 {
		work.NextStage = "complete"
		if !work.Configuration.Enabled || work.Text == "" {
			return s.repository.Save(ctx, work, work.Metadata)
		}
	} else if !work.Configuration.Enabled {
		return m.ErrStaleJob
	}
	key, err := s.repository.Credential(ctx, work.Configuration.CredentialID)
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return m.DocumentProcessingError{Code: "configuration_unavailable"}
	}
	values, err := s.extractor.ExtractProperties(ctx, work.Configuration, key, work.Text)
	if err != nil {
		return processingError(err)
	}
	values.Title = "extracted properties"
	values, err = values.Normalize()
	if err != nil {
		return m.DocumentProcessingError{Code: "processing_failed"}
	}
	return s.repository.Save(ctx, work, work.Metadata.FillExtractedProperties(values))
}
