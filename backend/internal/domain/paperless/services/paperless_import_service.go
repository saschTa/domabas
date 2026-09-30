package services

import (
	"context"
	"errors"
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/paperless/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

type PaperlessImportService struct {
	repository p.PaperlessRepository
	documents  p.PaperlessDocumentImporter
}

func NewPaperlessImportService(repository p.PaperlessRepository, documents p.PaperlessDocumentImporter) *PaperlessImportService {
	return &PaperlessImportService{repository: repository, documents: documents}
}
func (s *PaperlessImportService) Preview(ctx context.Context, connection m.PaperlessConnection, page int) (m.PaperlessPage, error) {
	if page < 1 {
		return m.PaperlessPage{}, m.PaperlessFailure{Code: "invalid_request"}
	}
	return s.repository.Preview(ctx, connection, page)
}
func (s *PaperlessImportService) Import(ctx context.Context, actor d.DocumentActor, connection m.PaperlessConnection, id int64) (m.PaperlessResult, error) {
	if id < 1 || id > 2147483647 {
		return m.PaperlessResult{}, m.PaperlessFailure{Code: "invalid_request"}
	}
	if actor.ImportRunID == "" {
		return m.PaperlessResult{}, d.ErrForbidden
	}
	reservation, err := s.documents.ReserveUpload(ctx, actor)
	if err != nil {
		return m.PaperlessResult{}, err
	}
	accepted := false
	defer func() {
		if !accepted {
			cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = s.documents.AbandonUpload(cleanup, actor, reservation)
		}
	}()
	original, err := s.repository.Original(ctx, connection, id)
	if err != nil {
		return m.PaperlessResult{}, err
	}
	defer original.Reader.Close()
	reference, err := s.documents.StageUpload(ctx, actor, reservation, original.Filename, original.Reader)
	if err != nil {
		return m.PaperlessResult{}, err
	}
	if reference.File.MediaType == "message/rfc822" {
		original.Metadata.Kind = "email"
	}
	doc, err := s.documents.AcceptUpload(ctx, actor, reservation, original.Metadata)
	if errors.Is(err, d.ErrDuplicate) {
		return m.PaperlessResult{Duplicate: true}, nil
	}
	if err != nil {
		return m.PaperlessResult{}, err
	}
	accepted = true
	return m.PaperlessResult{DocumentID: doc.ID}, nil
}
