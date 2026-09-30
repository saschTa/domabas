package models

import "time"

type DocumentJobHistoryRecord struct {
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
	Configuration                                               []byte
	TextSource                                                  *string
	CreatedAt, UpdatedAt                                        time.Time
	StartedAt, FinishedAt                                       *time.Time
	FailureCode                                                 *string
	IsCurrent, DocumentDeleted                                  bool
}
type DocumentJobCountRecord struct {
	Pipeline string
	Status   string
	Count    int64
}
type DocumentJobPageRecord struct {
	Counts     []DocumentJobCountRecord
	Items      []DocumentJobHistoryRecord
	NextCursor string
}
type DocumentReindexBatchRecord struct {
	ID, Scope, Reason, Status                                            string
	ConfigurationRevision                                                int64
	ConfigurationFingerprint                                             string
	CreatedAt                                                            time.Time
	FinishedAt                                                           *time.Time
	EnumerationComplete                                                  bool
	Discovered, Waiting, Running, Succeeded, Failed, Skipped, Superseded int64
}
type DocumentReindexStatusCountRecord struct {
	Status string
	Count  int64
}
type DocumentReindexBatchPageRecord struct {
	Counts     []DocumentReindexStatusCountRecord
	Items      []DocumentReindexBatchRecord
	NextCursor string
}
