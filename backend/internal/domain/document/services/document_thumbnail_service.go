package services

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"image/jpeg"
	"time"
)

type DocumentThumbnailService struct {
	repository p.DocumentThumbnailRepository
	content    p.DocumentContentStore
	renderer   p.DocumentThumbnailRenderer
	authority  p.DocumentAuthority
}

func NewDocumentThumbnailService(repository p.DocumentThumbnailRepository, content p.DocumentContentStore, renderer p.DocumentThumbnailRenderer, authority p.DocumentAuthority) *DocumentThumbnailService {
	return &DocumentThumbnailService{repository: repository, content: content, renderer: renderer, authority: authority}
}
func (s *DocumentThumbnailService) Read(ctx context.Context, a m.DocumentActor, id, expected string) (m.DocumentThumbnailContent, error) {
	if err := m.ValidateAccountID(a.AccountID); err != nil {
		return m.DocumentThumbnailContent{}, err
	}
	if len(expected) != 64 {
		return m.DocumentThumbnailContent{}, m.DocumentValidationError{Message: "expected thumbnail SHA-256 is required"}
	}
	decoded, err := hex.DecodeString(expected)
	if err != nil || len(decoded) != 32 {
		return m.DocumentThumbnailContent{}, m.DocumentValidationError{Message: "expected thumbnail SHA-256 is invalid"}
	}
	if _, err = resolveDocumentAuthority(ctx, s.authority, a, identity.DocumentsThumbnailsRead, identity.DocumentsDownload); err != nil {
		return m.DocumentThumbnailContent{}, err
	}
	result, err := s.repository.ReadThumbnail(ctx, a, id, expected)
	if err != nil {
		return result, err
	}
	if _, err = resolveDocumentAuthority(ctx, s.authority, a, identity.DocumentsThumbnailsRead, identity.DocumentsDownload); err != nil {
		return m.DocumentThumbnailContent{}, err
	}
	return result, nil
}
func (s *DocumentThumbnailService) Render(ctx context.Context, job m.DocumentThumbnailJob) error {
	work, err := s.repository.ThumbnailWork(ctx, job)
	if err != nil {
		return err
	}
	if work.Complete {
		return nil
	}
	stream, err := s.content.Open(ctx, work.Reference)
	if err != nil {
		return err
	}
	defer stream.Close()
	operation, cancel := context.WithTimeout(ctx, 75*time.Second)
	defer cancel()
	result, err := s.renderer.RenderThumbnail(operation, stream, work.Reference.File.MediaType)
	if err != nil {
		return err
	}
	if len(result.Bytes) == 0 || len(result.Bytes) > m.MaxThumbnailBytes || result.MediaType != "image/jpeg" || result.Width < 1 || result.Height < 1 || result.Width > m.MaxThumbnailWidth || result.Height > m.MaxThumbnailHeight {
		return m.DocumentProcessingError{Code: "invalid_file"}
	}
	config, err := jpeg.DecodeConfig(bytes.NewReader(result.Bytes))
	if err != nil || config.Width != result.Width || config.Height != result.Height {
		return m.DocumentProcessingError{Code: "invalid_file"}
	}
	if _, err = jpeg.Decode(bytes.NewReader(result.Bytes)); err != nil {
		return m.DocumentProcessingError{Code: "invalid_file"}
	}
	hash := sha256.Sum256(result.Bytes)
	content := m.DocumentThumbnailContent{Bytes: result.Bytes, Descriptor: m.DocumentThumbnail{SourceSHA256: job.SourceSHA256, SHA256: hex.EncodeToString(hash[:]), MediaType: "image/jpeg", Size: int64(len(result.Bytes)), Width: result.Width, Height: result.Height, RendererRevision: job.RendererRevision}}
	return s.repository.PublishThumbnail(ctx, job, content)
}
func (s *DocumentThumbnailService) Finish(ctx context.Context, job m.DocumentThumbnailJob, outcome m.DocumentThumbnailOutcome) error {
	return s.repository.FinishThumbnail(ctx, job, m.DocumentThumbnailCompletion(outcome))
}
func (s *DocumentThumbnailService) Discover(ctx context.Context) error {
	return s.repository.DiscoverThumbnails(ctx)
}
func (s *DocumentThumbnailService) Claim(ctx context.Context, queue string) ([]m.DocumentThumbnailJob, error) {
	return s.repository.ClaimThumbnails(ctx, queue)
}
func (s *DocumentThumbnailService) Acknowledge(ctx context.Context, job m.DocumentThumbnailJob, run string) error {
	return s.repository.AcknowledgeThumbnail(ctx, job, run)
}
func (s *DocumentThumbnailService) Release(ctx context.Context, job m.DocumentThumbnailJob) error {
	return s.repository.ReleaseThumbnail(ctx, job)
}
func (s *DocumentThumbnailService) Pending(ctx context.Context) ([]m.DocumentThumbnailJob, error) {
	return s.repository.PendingThumbnails(ctx)
}
func (s *DocumentThumbnailService) Resolve(ctx context.Context, job m.DocumentThumbnailJob, run string, closed, missing bool) error {
	return s.repository.ResolveThumbnail(ctx, job, run, closed, missing, m.DocumentThumbnailRetryDelay(job.Attempt))
}
