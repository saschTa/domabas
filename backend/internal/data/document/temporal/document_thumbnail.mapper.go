package temporal

import (
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	w "github.com/domabas/domabas/backend/internal/domain/document/workflows"
)

func thumbnailJobRequestMapper(j m.DocumentThumbnailJob) w.DocumentThumbnailRequest {
	return w.DocumentThumbnailRequest{JobID: j.ID, AccountID: j.AccountID, DocumentID: j.DocumentID, SourceSHA256: j.SourceSHA256, RendererRevision: j.RendererRevision, Attempt: j.Attempt}
}
func thumbnailRequestJobMapper(j w.DocumentThumbnailRequest) m.DocumentThumbnailJob {
	return m.DocumentThumbnailJob{ID: j.JobID, AccountID: j.AccountID, DocumentID: j.DocumentID, SourceSHA256: j.SourceSHA256, RendererRevision: j.RendererRevision, Attempt: j.Attempt}
}
