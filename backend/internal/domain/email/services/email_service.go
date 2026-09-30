package services

import (
	"context"
	"time"

	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailService struct {
	repository p.EmailRepository
	gateway    p.EmailGateway
	available  bool
	authority  p.EmailAuthority
}

func NewEmailService(repository p.EmailRepository, gateway p.EmailGateway, available bool, authority p.EmailAuthority) *EmailService {
	return &EmailService{repository: repository, gateway: gateway, available: available, authority: authority}
}
func (s *EmailService) Available() bool { return s.available }
func (s *EmailService) List(ctx context.Context, a m.EmailActor, limit int, cursor string) (m.EmailProviderPage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.EmailProviderPage{}, err
	}
	page, err := s.repository.List(ctx, a, limit, cursor)
	for index := range page.Items {
		page.Items[index].ConsentState = m.EmailConsentState(page.Items[index], a.CredentialRevision)
	}
	return page, err
}
func (s *EmailService) Get(ctx context.Context, a m.EmailActor, id string) (m.EmailProvider, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.EmailProvider{}, err
	}
	provider, err := s.repository.Get(ctx, a, id)
	provider.ConsentState = m.EmailConsentState(provider, a.CredentialRevision)
	return provider, err
}
func (s *EmailService) Create(ctx context.Context, a m.EmailActor, input m.EmailProviderInput) (m.EmailProvider, error) {
	if err := s.authorize(ctx, a, input.Enabled); err != nil {
		return m.EmailProvider{}, err
	}
	settings, err := input.EmailSettings.Normalize()
	if err != nil {
		return m.EmailProvider{}, err
	}
	input.EmailSettings = settings
	input.MaximumProviders = m.MaximumEmailProviders
	provider, err := s.repository.Create(ctx, a, input)
	provider.ConsentState = m.EmailConsentState(provider, a.CredentialRevision)
	return provider, err
}
func (s *EmailService) Update(ctx context.Context, a m.EmailActor, input m.EmailProviderInput) (m.EmailProvider, error) {
	if err := s.authorize(ctx, a, input.Enabled); err != nil {
		return m.EmailProvider{}, err
	}
	settings, err := input.EmailSettings.Normalize()
	if err != nil {
		return m.EmailProvider{}, err
	}
	if input.RenewConsent && !input.Enabled {
		return m.EmailProvider{}, m.EmailValidationError{Message: "consent renewal requires an enabled provider"}
	}
	input.EmailSettings = settings
	facts, err := s.repository.UpdateFacts(ctx, a, input.ID)
	if err != nil {
		return m.EmailProvider{}, err
	}
	command, err := m.PlanEmailProviderUpdate(facts, input, a.CredentialRevision)
	if err != nil {
		return m.EmailProvider{}, err
	}
	provider, err := s.repository.Update(ctx, a, command)
	provider.ConsentState = m.EmailConsentState(provider, a.CredentialRevision)
	return provider, err
}
func (s *EmailService) Delete(ctx context.Context, a m.EmailActor, id string, revision int64) error {
	if err := s.authorize(ctx, a, false); err != nil {
		return err
	}
	if revision < 1 {
		return m.EmailValidationError{Message: "expected revision must be positive"}
	}
	return s.repository.Delete(ctx, a, id, revision)
}
func (s *EmailService) Test(ctx context.Context, a m.EmailActor, input m.EmailTestConnection) (m.EmailTestResult, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.EmailTestResult{}, err
	}
	if (input.ProviderID == "") != (input.ExpectedRevision == nil) {
		return m.EmailTestResult{}, m.EmailValidationError{Message: "saved provider and expected revision must be supplied together"}
	}
	settings, err := (m.EmailSettings{Label: "connection test", Host: input.Host, Port: input.Port, Mailbox: input.Mailbox}).Normalize()
	if err != nil {
		return m.EmailTestResult{}, err
	}
	input.Host, input.Port, input.Mailbox = settings.Host, settings.Port, settings.Mailbox
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	token, err := s.repository.BeginTest(ctx, a, m.DefaultEmailTestAdmission())
	if err != nil {
		return m.EmailTestResult{}, err
	}
	defer func() {
		cleanup, stop := context.WithTimeout(context.WithoutCancel(ctx), time.Second)
		defer stop()
		_ = s.repository.EndTest(cleanup, a, token)
	}()
	connection, err := s.repository.TestCredentials(ctx, a, input)
	if err != nil {
		return m.EmailTestResult{}, err
	}
	mailbox, err := s.gateway.Connect(ctx, connection)
	if err != nil {
		return m.EmailTestResult{}, err
	}
	info := mailbox.Info()
	if err = mailbox.Close(); err != nil {
		return m.EmailTestResult{}, m.EmailFailure{Code: "connection_failed", Retryable: true}
	}
	if err = s.authorize(ctx, a, false); err != nil {
		return m.EmailTestResult{}, err
	}
	if err = s.repository.VerifyTest(ctx, a, input); err != nil {
		return m.EmailTestResult{}, err
	}
	return m.EmailTestResult{UIDValidity: info.UIDValidity}, nil
}
func (s *EmailService) Runs(ctx context.Context, a m.EmailActor, q m.EmailRunQuery) (m.EmailRunPage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.EmailRunPage{}, err
	}
	if err := q.Validate(); err != nil {
		return m.EmailRunPage{}, err
	}
	return s.repository.Runs(ctx, a, q)
}
func (s *EmailService) Run(ctx context.Context, a m.EmailActor, id string) (m.EmailRun, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.EmailRun{}, err
	}
	return s.repository.Run(ctx, a, id)
}
func (s *EmailService) Start(ctx context.Context, a m.EmailActor, id string, input m.EmailStartRun) (m.EmailRun, error) {
	if err := s.authorize(ctx, a, true); err != nil {
		return m.EmailRun{}, err
	}
	if input.ExpectedRevision < 1 {
		return m.EmailRun{}, m.EmailValidationError{Message: "expected revision must be positive"}
	}
	requested, err := s.repository.RequestedRun(ctx, a, id, input)
	if err != nil {
		return m.EmailRun{}, err
	}
	if requested != nil {
		return *requested, nil
	}
	facts, err := s.repository.UpdateFacts(ctx, a, id)
	if err != nil {
		return m.EmailRun{}, err
	}
	command, err := m.PlanEmailStart(facts, input, a.CredentialRevision)
	if err != nil {
		return m.EmailRun{}, err
	}
	return s.repository.Start(ctx, a, id, command)
}
func (s *EmailService) Rotate(ctx context.Context) error { return s.repository.Rotate(ctx, 50) }
