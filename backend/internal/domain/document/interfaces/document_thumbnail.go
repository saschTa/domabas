package interfaces

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"io"
	"time"
)

type DocumentThumbnailRenderer interface {
	RenderThumbnail(context.Context, io.Reader, string) (m.DocumentThumbnailImage, error)
}
type DocumentThumbnailRepository interface {
	DiscoverThumbnails(context.Context) error
	ClaimThumbnails(context.Context, string) ([]m.DocumentThumbnailJob, error)
	AcknowledgeThumbnail(context.Context, m.DocumentThumbnailJob, string) error
	ReleaseThumbnail(context.Context, m.DocumentThumbnailJob) error
	PendingThumbnails(context.Context) ([]m.DocumentThumbnailJob, error)
	ResolveThumbnail(context.Context, m.DocumentThumbnailJob, string, bool, bool, time.Duration) error
	ThumbnailWork(context.Context, m.DocumentThumbnailJob) (m.DocumentThumbnailWork, error)
	PublishThumbnail(context.Context, m.DocumentThumbnailJob, m.DocumentThumbnailContent) error
	FinishThumbnail(context.Context, m.DocumentThumbnailJob, m.DocumentThumbnailOutcome) error
	ReadThumbnail(context.Context, m.DocumentActor, string, string) (m.DocumentThumbnailContent, error)
}
