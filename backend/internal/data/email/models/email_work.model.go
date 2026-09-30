package models

import "time"

type EmailWorkRecord struct {
	Attempt  EmailAttempt
	Run      EmailRun
	Provider EmailProviderRecord
}

type EmailAttempt struct {
	RunID, WorkflowID, WorkflowRunID, TaskQueue, ActivityID, Token string
	PageIndex, Number                                              int
	Deadline                                                       time.Time
	ExecutionStartedAt                                             time.Time
	ConsentRevision                                                int64
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
