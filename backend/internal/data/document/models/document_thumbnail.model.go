package models

import "time"

type DocumentThumbnailRecord struct {
	SourceSHA256, SHA256, MediaType string
	Size                            int64
	Width, Height, RendererRevision int
}

type DocumentThumbnailJobRecord struct {
	ID, AccountID, DocumentID, SourceSHA256          string
	RendererRevision, Attempt                        int
	WorkflowID, RunID, TaskQueue, LeaseToken, Status string
	PermitEnd, AdmittedAt                            time.Time
}
type DocumentThumbnailWorkRecord struct {
	Reference DocumentReferenceRecord
	Complete  bool
}
type DocumentThumbnailContentRecord struct {
	Descriptor DocumentThumbnailRecord
	Bytes      []byte
}
