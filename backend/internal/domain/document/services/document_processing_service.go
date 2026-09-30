package services

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (s *DocumentIngestionService) Work(ctx context.Context, job m.DocumentJob, requested string) (m.DocumentProcessingWork, error) {
	work, err := s.repository.Work(ctx, job, requested)
	if err != nil {
		return work, err
	}
	command, err := m.PlanDocumentProcessing(work, requested)
	if err != nil {
		return work, err
	}
	if err = s.repository.BeginWork(ctx, command); err != nil {
		return work, err
	}
	if !command.Replay {
		work.State = command.State
		work.Stage = command.Stage
	}
	return work, nil
}
func (s *DocumentIngestionService) SaveExtraction(ctx context.Context, job m.DocumentJob, revision int64, text string, invoiceXML ...[]byte) error {
	extraction := m.DocumentExtraction{Text: text}
	if len(invoiceXML) > 0 {
		extraction.InvoiceXML = invoiceXML[0]
	}
	return s.SaveExtractionEvidence(ctx, job, revision, extraction)
}
func (s *DocumentIngestionService) SaveExtractionEvidence(ctx context.Context, job m.DocumentJob, revision int64, extraction m.DocumentExtraction) error {
	work, err := s.repository.Work(ctx, job, "extracting")
	if err != nil {
		return err
	}
	command, err := m.PlanDocumentExtraction(work, revision, extraction)
	if err != nil {
		return err
	}
	return s.repository.SaveExtractionEvidence(ctx, command)
}
func (s *DocumentIngestionService) SaveEmbeddings(ctx context.Context, job m.DocumentJob, revision int64, space m.DocumentEmbeddingSpace, chunks []m.DocumentChunk) error {
	work, err := s.repository.Work(ctx, job, "embedding")
	if err != nil {
		return err
	}
	command, err := m.PlanDocumentEmbeddings(work, revision, space, chunks)
	if err != nil {
		return err
	}
	return s.repository.SaveEmbeddings(ctx, command)
}
func (s *DocumentIngestionService) Publish(ctx context.Context, job m.DocumentJob, revision int64) error {
	work, err := s.repository.Work(ctx, job, "finalizing")
	if err != nil {
		return err
	}
	command, err := m.PlanDocumentPublication(work, revision)
	if err != nil {
		return err
	}
	return s.repository.Publish(ctx, command)
}
