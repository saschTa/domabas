package models

import "time"

type DocumentAIProcessingRecord struct {
	InvoiceDecision, InvoiceDecisionReason                                     string
	InvoiceClassificationPass, InvoiceInputCharacters, InvoiceSourceCharacters int

	JobID, Status, Stage           string
	Attempt, ConfigurationRevision int64
	FailureCode                    *string
	UpdatedAt                      time.Time
	StartedAt, FinishedAt          *time.Time
}
