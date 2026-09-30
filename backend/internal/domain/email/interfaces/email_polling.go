package interfaces

import (
	"context"
	"io"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailDocumentImporter interface {
	Reserve(context.Context, d.DocumentImportAuthority) (d.DocumentUploadReservation, error)
	Stage(context.Context, d.DocumentImportAuthority, d.DocumentUploadReservation, string, io.Reader) (d.DocumentMetadata, error)
	Accept(context.Context, d.DocumentImportAuthority, d.DocumentUploadReservation, d.DocumentMetadata) (d.DocumentImportResult, error)
	Inspect(context.Context, d.DocumentImportAuthority, func(d.DocumentEmailPart) error) (d.DocumentEmailInspection, error)
}
type EmailPollingRepository interface {
	Retire(context.Context, m.EmailRetirementCommand) error
	Consent(context.Context, string) (m.EmailProvider, error)
	ClaimAttempt(context.Context, m.EmailAttempt, m.EmailAttemptAdmission) (m.EmailWork, error)
	MailboxFacts(context.Context, m.EmailAttempt) (m.EmailMailboxFacts, error)
	SetupMailbox(context.Context, m.EmailAttempt, m.EmailMailboxCommand) (m.EmailCursor, error)
	PendingItems(context.Context, m.EmailAttempt, m.EmailPendingQuery) ([]m.EmailItem, error)
	DiscoverItems(context.Context, m.EmailAttempt, m.EmailDiscoveryCommand) ([]m.EmailItem, error)
	Part(context.Context, m.EmailAttempt, m.EmailItem, string, string, string) (m.EmailPart, error)
	PartFacts(context.Context, m.EmailAttempt, m.EmailItem, m.EmailPart) (m.EmailPartFacts, error)
	PartOutcome(context.Context, m.EmailAttempt, m.EmailItem, m.EmailPart, m.EmailPartOutcomeCommand) error
	MessageFacts(context.Context, m.EmailAttempt, m.EmailItem) (m.EmailMessageFacts, error)
	MessageOutcome(context.Context, m.EmailAttempt, m.EmailItem, m.EmailMessageOutcomeCommand) error
	InspectionOutcome(context.Context, m.EmailAttempt, m.EmailItem, m.EmailInspectionCommand) error
	SetStage(context.Context, m.EmailAttempt, string) error
	HasMore(context.Context, m.EmailAttempt) (bool, error)
	FinishFacts(context.Context, m.EmailAttempt) (m.EmailRunFinishFacts, error)
	Finish(context.Context, m.EmailRunFinishCommand) error
}
type EmailDispatchRepository interface {
	ScheduleCandidates(context.Context) ([]m.EmailScheduleCandidate, error)
	ScheduleProvider(context.Context, m.EmailScheduleCandidate, string) error
	Retire(context.Context, m.EmailRetirementCommand) error
	NextDelivery(context.Context) (string, error)
	ClaimDelivery(context.Context, string, string) (*m.EmailExecution, error)
	AcknowledgeDelivery(context.Context, m.EmailExecution, string) error
	PendingExecutions(context.Context) ([]m.EmailExecution, error)
	ExecutionFacts(context.Context, m.EmailExecution) (m.EmailExecutionFacts, error)
	ResolveExecution(context.Context, m.EmailExecutionClosureCommand) error
	Cleanup(context.Context) error
}
