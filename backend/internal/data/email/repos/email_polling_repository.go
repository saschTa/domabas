package repos

import (
	"context"

	r "github.com/domabas/domabas/backend/internal/data/email/models"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailPollingSource interface {
	Retire(context.Context, m.EmailRetirementCommand) error
	Consent(context.Context, string) (m.EmailProvider, error)
	ScheduleCandidates(context.Context, ...string) ([]m.EmailScheduleCandidate, error)
	ScheduleProvider(context.Context, m.EmailScheduleCandidate, string, ...string) error
	NextDelivery(context.Context, ...string) (string, error)
	ClaimDeliveryFor(context.Context, string, string, ...string) (*m.EmailExecution, error)
	AcknowledgeDelivery(context.Context, m.EmailExecution, string) error
	PendingExecutions(context.Context) ([]m.EmailExecution, error)
	ExecutionFacts(context.Context, m.EmailExecution) (m.EmailExecutionFacts, error)
	ResolveExecution(context.Context, m.EmailExecutionClosureCommand) error
	Cleanup(context.Context) error
	ClaimAttempt(context.Context, m.EmailAttempt, m.EmailAttemptAdmission) (r.EmailWorkRecord, error)
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
type EmailPollingRepository struct {
	source EmailPollingSource
	vault  p.EmailCredentialVault
}

func NewEmailPollingRepository(source EmailPollingSource, vault p.EmailCredentialVault) *EmailPollingRepository {
	return &EmailPollingRepository{source: source, vault: vault}
}
func (s *EmailPollingRepository) Consent(ctx context.Context, id string) (m.EmailProvider, error) {
	return s.source.Consent(ctx, id)
}
func (s *EmailPollingRepository) Retire(ctx context.Context, command m.EmailRetirementCommand) error {
	return s.source.Retire(ctx, command)
}
func (s *EmailPollingRepository) ClaimAttempt(ctx context.Context, a m.EmailAttempt, admission m.EmailAttemptAdmission) (m.EmailWork, error) {
	record, err := s.source.ClaimAttempt(ctx, a, admission)
	if err != nil {
		return m.EmailWork{}, err
	}
	credentials, err := s.vault.Open(emailCredentialIdentityMapper(record.Provider), record.Provider.KeyID, record.Provider.Ciphertext)
	if err != nil {
		return m.EmailWork{}, m.EmailFailure{Code: "credentials_unavailable"}
	}
	work := m.EmailWork{Attempt: m.EmailAttempt(record.Attempt), Run: m.EmailRun(record.Run), Provider: emailProviderValueToDomainMapper(record.Provider.Provider)}
	work.Connection = m.EmailConnection{Host: work.Provider.Host, Port: work.Provider.Port, Mailbox: work.Provider.Mailbox, Credentials: credentials}
	return work, nil
}
func (s *EmailPollingRepository) MailboxFacts(ctx context.Context, a m.EmailAttempt) (m.EmailMailboxFacts, error) {
	return s.source.MailboxFacts(ctx, a)
}
func (s *EmailPollingRepository) SetupMailbox(ctx context.Context, a m.EmailAttempt, command m.EmailMailboxCommand) (m.EmailCursor, error) {
	return s.source.SetupMailbox(ctx, a, command)
}
func (s *EmailPollingRepository) PendingItems(ctx context.Context, a m.EmailAttempt, query m.EmailPendingQuery) ([]m.EmailItem, error) {
	return s.source.PendingItems(ctx, a, query)
}
func (s *EmailPollingRepository) DiscoverItems(ctx context.Context, a m.EmailAttempt, command m.EmailDiscoveryCommand) ([]m.EmailItem, error) {
	return s.source.DiscoverItems(ctx, a, command)
}
func (s *EmailPollingRepository) Part(ctx context.Context, a m.EmailAttempt, item m.EmailItem, path, name, media string) (m.EmailPart, error) {
	return s.source.Part(ctx, a, item, path, name, media)
}
func (s *EmailPollingRepository) PartFacts(ctx context.Context, a m.EmailAttempt, item m.EmailItem, part m.EmailPart) (m.EmailPartFacts, error) {
	return s.source.PartFacts(ctx, a, item, part)
}
func (s *EmailPollingRepository) PartOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, part m.EmailPart, command m.EmailPartOutcomeCommand) error {
	return s.source.PartOutcome(ctx, a, item, part, command)
}
func (s *EmailPollingRepository) MessageFacts(ctx context.Context, a m.EmailAttempt, item m.EmailItem) (m.EmailMessageFacts, error) {
	return s.source.MessageFacts(ctx, a, item)
}
func (s *EmailPollingRepository) MessageOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, command m.EmailMessageOutcomeCommand) error {
	return s.source.MessageOutcome(ctx, a, item, command)
}
func (s *EmailPollingRepository) InspectionOutcome(ctx context.Context, a m.EmailAttempt, item m.EmailItem, command m.EmailInspectionCommand) error {
	return s.source.InspectionOutcome(ctx, a, item, command)
}
func (s *EmailPollingRepository) SetStage(ctx context.Context, a m.EmailAttempt, stage string) error {
	return s.source.SetStage(ctx, a, stage)
}
func (s *EmailPollingRepository) HasMore(ctx context.Context, a m.EmailAttempt) (bool, error) {
	return s.source.HasMore(ctx, a)
}
func (s *EmailPollingRepository) FinishFacts(ctx context.Context, a m.EmailAttempt) (m.EmailRunFinishFacts, error) {
	return s.source.FinishFacts(ctx, a)
}
func (s *EmailPollingRepository) Finish(ctx context.Context, command m.EmailRunFinishCommand) error {
	return s.source.Finish(ctx, command)
}
func (s *EmailPollingRepository) ScheduleCandidates(ctx context.Context) ([]m.EmailScheduleCandidate, error) {
	if !s.vault.Available() {
		return nil, nil
	}
	return s.source.ScheduleCandidates(ctx, s.vault.KeyIDs()...)
}
func (s *EmailPollingRepository) ScheduleProvider(ctx context.Context, c m.EmailScheduleCandidate, trigger string) error {
	return s.source.ScheduleProvider(ctx, c, trigger, s.vault.KeyIDs()...)
}
func (s *EmailPollingRepository) NextDelivery(ctx context.Context) (string, error) {
	if !s.vault.Available() {
		return "", nil
	}
	return s.source.NextDelivery(ctx, s.vault.KeyIDs()...)
}
func (s *EmailPollingRepository) ClaimDelivery(ctx context.Context, queue, runID string) (*m.EmailExecution, error) {
	if !s.vault.Available() {
		return nil, nil
	}
	return s.source.ClaimDeliveryFor(ctx, queue, runID, s.vault.KeyIDs()...)
}
func (s *EmailPollingRepository) AcknowledgeDelivery(ctx context.Context, e m.EmailExecution, run string) error {
	return s.source.AcknowledgeDelivery(ctx, e, run)
}
func (s *EmailPollingRepository) PendingExecutions(ctx context.Context) ([]m.EmailExecution, error) {
	return s.source.PendingExecutions(ctx)
}
func (s *EmailPollingRepository) ExecutionFacts(ctx context.Context, e m.EmailExecution) (m.EmailExecutionFacts, error) {
	return s.source.ExecutionFacts(ctx, e)
}
func (s *EmailPollingRepository) ResolveExecution(ctx context.Context, command m.EmailExecutionClosureCommand) error {
	return s.source.ResolveExecution(ctx, command)
}
func (s *EmailPollingRepository) Cleanup(ctx context.Context) error { return s.source.Cleanup(ctx) }
