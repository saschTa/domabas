package repos

import (
	"context"
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"time"
)

type DocumentThumbnailSource interface {
	DiscoverThumbnails(context.Context) error
	ClaimThumbnailRecords(context.Context, string) ([]r.DocumentThumbnailJobRecord, error)
	AcknowledgeThumbnail(context.Context, m.DocumentThumbnailJob, string) error
	ReleaseThumbnail(context.Context, m.DocumentThumbnailJob) error
	PendingThumbnailRecords(context.Context) ([]r.DocumentThumbnailJobRecord, error)
	ResolveThumbnail(context.Context, m.DocumentThumbnailJob, string, bool, bool, time.Duration) error
	ThumbnailWorkRecord(context.Context, m.DocumentThumbnailJob) (r.DocumentThumbnailWorkRecord, error)
	PublishThumbnail(context.Context, m.DocumentThumbnailJob, m.DocumentThumbnailContent) error
	FinishThumbnail(context.Context, m.DocumentThumbnailJob, m.DocumentThumbnailOutcome) error
	ReadThumbnailRecord(context.Context, m.DocumentActor, string, string) (r.DocumentThumbnailContentRecord, error)
}
type DocumentThumbnailRepository struct{ source DocumentThumbnailSource }

func NewDocumentThumbnailRepository(source DocumentThumbnailSource) *DocumentThumbnailRepository {
	return &DocumentThumbnailRepository{source: source}
}
func (r *DocumentThumbnailRepository) DiscoverThumbnails(c context.Context) error {
	return r.source.DiscoverThumbnails(c)
}
func (r *DocumentThumbnailRepository) ClaimThumbnails(c context.Context, q string) ([]m.DocumentThumbnailJob, error) {
	records, err := r.source.ClaimThumbnailRecords(c, q)
	return documentThumbnailJobsMapper(records), err
}
func (r *DocumentThumbnailRepository) AcknowledgeThumbnail(c context.Context, j m.DocumentThumbnailJob, run string) error {
	return r.source.AcknowledgeThumbnail(c, j, run)
}
func (r *DocumentThumbnailRepository) ReleaseThumbnail(c context.Context, j m.DocumentThumbnailJob) error {
	return r.source.ReleaseThumbnail(c, j)
}
func (r *DocumentThumbnailRepository) PendingThumbnails(c context.Context) ([]m.DocumentThumbnailJob, error) {
	records, err := r.source.PendingThumbnailRecords(c)
	return documentThumbnailJobsMapper(records), err
}
func (r *DocumentThumbnailRepository) ResolveThumbnail(c context.Context, j m.DocumentThumbnailJob, run string, closed, missing bool, delay time.Duration) error {
	return r.source.ResolveThumbnail(c, j, run, closed, missing, delay)
}
func (r *DocumentThumbnailRepository) ThumbnailWork(c context.Context, j m.DocumentThumbnailJob) (m.DocumentThumbnailWork, error) {
	record, err := r.source.ThumbnailWorkRecord(c, j)
	return m.DocumentThumbnailWork{Complete: record.Complete, Reference: documentReferenceRecordToDomainMapper(record.Reference)}, err
}
func (r *DocumentThumbnailRepository) PublishThumbnail(c context.Context, j m.DocumentThumbnailJob, v m.DocumentThumbnailContent) error {
	return r.source.PublishThumbnail(c, j, v)
}
func (r *DocumentThumbnailRepository) FinishThumbnail(c context.Context, j m.DocumentThumbnailJob, v m.DocumentThumbnailOutcome) error {
	return r.source.FinishThumbnail(c, j, v)
}
func (r *DocumentThumbnailRepository) ReadThumbnail(c context.Context, a m.DocumentActor, id, sha string) (m.DocumentThumbnailContent, error) {
	record, err := r.source.ReadThumbnailRecord(c, a, id, sha)
	return m.DocumentThumbnailContent{Descriptor: m.DocumentThumbnail(record.Descriptor), Bytes: record.Bytes}, err
}
