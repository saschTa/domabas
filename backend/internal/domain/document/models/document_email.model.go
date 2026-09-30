package models

import (
	"io"
	"time"
)

type DocumentImportAuthority struct {
	ProviderID, OwnerID, AccountID, RunID, MessageID, PartID, AttemptToken, WorkflowRunID, ActivityID string
	ProviderRevision, SourceGeneration, MailboxGeneration                                             int64
	CredentialRevision                                                                                int64
	PageIndex, ActivityAttempt                                                                        int
	AttemptDeadline                                                                                   time.Time
}
type DocumentImportResult struct {
	DocumentID string
	Reused     bool
}
type DocumentEmailPart struct {
	Path, Filename, MediaType, Status, FailureCode string
	Reader                                         io.Reader
}
type DocumentEmailInspection struct {
	Metadata        DocumentMetadata
	ContentFailures bool
}
type DocumentEmailLink struct {
	DocumentID, Title, MediaType string
	CreatedAt                    time.Time
}
type DocumentEmailAttachment struct {
	Part, Filename, Status, FailureCode string
	Document                            *DocumentEmailLink
}
type DocumentEmailLinks struct {
	Attachments []DocumentEmailAttachment
	NextCursor  string
}
type DocumentEmailParents struct {
	Items      []DocumentEmailLink
	NextCursor string
}
