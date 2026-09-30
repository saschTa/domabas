package models

import (
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type PaperlessRun struct {
	ID, ServerURL, State, Stage, FailureCode string
	Discovered, Imported, Duplicates, Failed int
	CancelRequested                          bool
	CreatedAt, UpdatedAt                     time.Time
	Outcomes                                 []PaperlessOutcome
}
type PaperlessOutcome struct {
	ClaimToken                             string
	SourceID                               int64
	Title, Status, FailureCode, DocumentID string
}
type PaperlessWork struct {
	Run        PaperlessRun
	Actor      d.DocumentActor
	Connection PaperlessConnection
	Page       int
	Items      []PaperlessRetrieval
	Waiting    bool
}
type PaperlessRetrieval struct {
	Document   PaperlessDocument
	ClaimToken string
	Deadline   time.Time
}
type PaperlessExecution struct {
	ID, TaskQueue string
	FirstStart    time.Time
}

type PaperlessPageRequest struct {
	ActiveOnly bool
	Limit      int
	Cursor     string
	Status     string
	Projection PaperlessStatusProjection
}
type PaperlessJobStatusCount struct {
	Status string
	Count  int64
}
type PaperlessRunPage struct {
	Counts     []PaperlessJobStatusCount
	Items      []PaperlessRun
	NextCursor string
}
type PaperlessOutcomePage struct {
	Items      []PaperlessOutcome
	NextCursor string
}
