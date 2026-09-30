package models

import (
	"errors"
	"io"
	"time"
)

var ErrNotFound = errors.New("email resource not found")
var ErrForbidden = errors.New("email permission denied")
var ErrConflict = errors.New("email resource changed")
var ErrUnavailable = errors.New("email ingestion unavailable")
var ErrRateLimited = errors.New("email operation rate limited")
var ErrStaleAttempt = errors.New("email attempt is no longer current")

type EmailValidationError struct{ Message string }

func (e EmailValidationError) Error() string { return e.Message }

type EmailFailure struct {
	Code      string
	Retryable bool
}

func (e EmailFailure) Error() string { return e.Code }

type EmailActor struct {
	AccountID, UserID, SessionDigest string
	CredentialRevision               int64
}
type EmailCredentials struct{ Username, Password string }
type EmailCredentialIdentity struct{ ProviderID, OwnerID, AccountID string }
type EmailConnection struct {
	Host, Mailbox string
	Port          int
	Credentials   EmailCredentials
}
type EmailSettings struct {
	Label, Host, Mailbox                        string
	Port, IntervalMinutes, MaxAgeDays, PageSize int
	Enabled                                     bool
}
type EmailProvider struct {
	ID, OwnerID, AccountID string
	EmailSettings
	Revision, SourceGeneration, CredentialVersion            int64
	ConsentRevision                                          int64
	ConsentState, CredentialState, Username, LastFailureCode string
	HasPassword                                              bool
	NextPollAt                                               *time.Time
	LastRunID, LastRunStatus, ActiveRunID                    string
	LastAttemptAt                                            *time.Time
	CreatedAt, UpdatedAt                                     time.Time
}
type EmailProviderInput struct {
	ID               string
	MaximumProviders int
	EmailSettings
	Username, Password *string
	ExpectedRevision   *int64
	RenewConsent       bool
}
type EmailProviderPage struct {
	Items      []EmailProvider
	NextCursor string
}
type EmailRun struct {
	ID, ProviderID, OwnerID, AccountID, Trigger, Status, Stage, FailureCode, RequestID                                 string
	ProviderRevision, SourceGeneration, MailboxGeneration                                                              int64
	MessagesDiscovered, MessagesAccepted, MessagesReused, MessagesSkipped, MessagesFailed, MessagesWithContentFailures int64
	AttachmentsAccepted, AttachmentsReused, AttachmentsSkipped, AttachmentsFailed                                      int64
	HasMore                                                                                                            bool
	CreatedAt                                                                                                          time.Time
	StartedAt, FinishedAt                                                                                              *time.Time
}
type EmailJobStatusCount struct {
	Status string
	Count  int64
}
type EmailRunPage struct {
	Counts     []EmailJobStatusCount
	Items      []EmailRun
	NextCursor string
}

type EmailRunQuery struct {
	ActiveOnly                 bool
	ProviderID, Status, Cursor string
	Limit                      int
}
type EmailStartRun struct {
	RequestID        string
	ExpectedRevision int64
}
type EmailTestConnection struct {
	ProviderID       string
	ExpectedRevision *int64
	EmailConnection
	Username, Password *string
}
type EmailTestResult struct {
	UIDValidity  int64
	MessageCount int64
}
type EmailAttempt struct {
	RunID, WorkflowID, WorkflowRunID, TaskQueue, ActivityID, Token string
	PageIndex, Number                                              int
	Deadline                                                       time.Time
	ExecutionStartedAt                                             time.Time
	ConsentRevision                                                int64
}
type EmailWork struct {
	Attempt    EmailAttempt
	Provider   EmailProvider
	Connection EmailConnection
	Run        EmailRun
}
type EmailMailbox struct{ UIDValidity, UIDNext int64 }
type EmailDiscovery struct {
	UIDs    []int64
	Through int64
}
type EmailMessage struct {
	UID          int64
	InternalDate time.Time
	Size         int64
	Reader       io.Reader
}
type EmailItem struct {
	ID, RunID, ProviderID, AccountID, OwnerID, State, ParentDocumentID, InspectionState string
	ProviderRevision, SourceGeneration, MailboxGeneration, UID                          int64
	InternalDate                                                                        time.Time
}
type EmailPart struct{ ID, MessageID, Path, Filename, State, FailureCode, DocumentID string }
type EmailExecution struct {
	RunID, WorkflowID, WorkflowRunID, TaskQueue, LeaseToken        string
	FirstAttemptAt, StartWindowEnd, LatestPermitEnd, NextAttemptAt time.Time
	Closed, Terminal                                               bool
}
type EmailPageResult struct{ HasMore bool }

type EmailScheduleCandidate struct {
	ProviderID, AccountID, OwnerID                      string
	ProviderRevision, SourceGeneration, ConsentRevision int64
	HasMore                                             bool
}

type EmailCursor struct {
	MailboxGeneration, LiveNext, LiveUpper, BackfillNext, BackfillUpper int64
	BackfillTurn, RetryTurn                                             bool
}
