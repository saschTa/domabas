package models

import "time"

type DocumentReindexCandidate struct {
	ID, AccountID   string
	Sequence        int64
	Original        bool
	AlreadyEnrolled bool
}
type DocumentReindexEnumeration struct {
	BatchID        string
	AccountID      *string
	Cutoff, Cursor int64
	Candidates     []DocumentReindexCandidate
}
type DocumentReindexOutcomeFacts struct {
	BatchID, DocumentID, ItemStatus, BatchStatus, JobStatus string
	FailureCode                                             *string
	Deleted                                                 bool
}
type DocumentReindexCounts struct{ Discovered, Waiting, Running, Succeeded, Failed, Skipped, Superseded int64 }
type DocumentReindexAggregateFacts struct {
	BatchID, Status     string
	EnumerationComplete bool
	Counts              DocumentReindexCounts
}
type DocumentReindexMaintenanceFacts struct {
	Enumeration *DocumentReindexEnumeration
	Outcomes    []DocumentReindexOutcomeFacts
	Aggregates  []DocumentReindexAggregateFacts
}
type DocumentReindexItemChange struct {
	BatchID, AccountID, DocumentID, Status string
	OutcomeCode                            *string
	ClearJob                               bool
}
type DocumentReindexAggregateChange struct {
	BatchID, Status string
	Counts          DocumentReindexCounts
	Finished        bool
}
type DocumentReindexMaintenanceCommand struct {
	Expected             DocumentReindexMaintenanceFacts
	Insertions, Outcomes []DocumentReindexItemChange
	Cursor               int64
	EnumerationComplete  bool
	EnumerationStatus    string
	Aggregates           []DocumentReindexAggregateChange
	RecheckAfter         time.Duration
}
type DocumentReindexScheduleFacts struct {
	BatchID, AccountID, DocumentID, Reason         string
	Cutoff, ConfigurationRevision                  int64
	Configuration                                  DocumentProcessingConfiguration
	Exists, Original                               bool
	ProcessingState, Fingerprint, JobID, JobStatus string
	Generation, Sequence                           int64
	Extraction                                     bool
	MachineFingerprint                             *string
}
type DocumentReindexScheduleCommand struct {
	Expected       DocumentReindexScheduleFacts
	Action, Status string
	OutcomeCode    *string
	RecheckAfter   time.Duration
}
