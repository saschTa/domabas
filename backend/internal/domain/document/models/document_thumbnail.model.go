package models

import "time"

const (
	MaxThumbnailWidth         = 256
	MaxThumbnailHeight        = 360
	MaxThumbnailBytes         = 256 << 10
	ThumbnailRendererRevision = 1
)

type DocumentThumbnailImage struct {
	Bytes         []byte
	Width, Height int
	MediaType     string
}
type DocumentThumbnail struct {
	SourceSHA256, SHA256, MediaType string
	Size                            int64
	Width, Height, RendererRevision int
}
type DocumentThumbnailContent struct {
	Descriptor DocumentThumbnail
	Bytes      []byte
}
type DocumentThumbnailJob struct {
	ID, AccountID, DocumentID, SourceSHA256          string
	RendererRevision, Attempt                        int
	WorkflowID, RunID, TaskQueue, LeaseToken, Status string
	PermitEnd, AdmittedAt                            time.Time
}
type DocumentThumbnailWork struct {
	Reference DocumentFileReference
	Complete  bool
}
type DocumentThumbnailOutcome struct {
	FailureCode, Status string
	Retryable           bool
}
