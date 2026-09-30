package workflows

type DocumentThumbnailRequest struct {
	JobID            string `json:"jobId"`
	AccountID        string `json:"accountId"`
	DocumentID       string `json:"documentId"`
	SourceSHA256     string `json:"sourceSha256"`
	RendererRevision int    `json:"rendererRevision"`
	Attempt          int    `json:"attempt"`
}
type DocumentThumbnailResult struct {
	FailureCode string `json:"failureCode,omitempty"`
	Retryable   bool   `json:"retryable,omitempty"`
}
type DocumentThumbnailFailure struct {
	Request DocumentThumbnailRequest `json:"request"`
	Outcome DocumentThumbnailResult  `json:"outcome"`
}
