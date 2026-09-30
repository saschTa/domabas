package models

import "time"

type DocumentJobHistory struct {
	InvoiceDecision, InvoiceDecisionReason                                     string
	InvoiceClassificationPass, InvoiceInputCharacters, InvoiceSourceCharacters int

	Pipeline                                                    string
	RendererRevision                                            *int
	PipelineVersion                                             int
	Attempt                                                     *int64
	ExtractionMethod, ExtractionEngine, ExtractionEngineVersion string
	ID, DocumentID                                              string
	DocumentTitle                                               *string
	Generation                                                  *int64
	Reason, Status, Stage                                       string
	ConfigurationRevision                                       *int64
	ConfigurationFingerprint                                    *string
	Configuration                                               *DocumentProcessingConfiguration
	TextSource                                                  *string
	CreatedAt, UpdatedAt                                        time.Time
	StartedAt, FinishedAt                                       *time.Time
	FailureCode                                                 *string
	IsCurrent, DocumentDeleted                                  bool
}
type DocumentProcessingPageInput struct {
	ActiveOnly                           bool
	Limit                                int
	Cursor, Status, DocumentID, Pipeline string
}
type DocumentJobProjection struct {
	IncludeTitles bool
}
type DocumentJobCount struct {
	Pipeline string
	Status   string
	Count    int64
}
type DocumentJobPage struct {
	Counts     []DocumentJobCount
	Items      []DocumentJobHistory
	NextCursor string
}
type DocumentReindexRequest struct {
	RequestID             string
	ConfigurationRevision int64
}
type DocumentReindexBatch struct {
	ID, Scope, Reason, Status                                            string
	ConfigurationRevision                                                int64
	ConfigurationFingerprint                                             string
	CreatedAt                                                            time.Time
	FinishedAt                                                           *time.Time
	EnumerationComplete                                                  bool
	Discovered, Waiting, Running, Succeeded, Failed, Skipped, Superseded int64
}
type DocumentReindexStatusCount struct {
	Status string
	Count  int64
}
type DocumentReindexBatchPage struct {
	Counts     []DocumentReindexStatusCount
	Items      []DocumentReindexBatch
	NextCursor string
}

type DocumentEmbeddingSpace struct {
	Model, Digest                            string
	Dimensions                               int
	EmbeddingInputRevision, IndexingRevision string
}
