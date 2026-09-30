package repos

import (
	"context"
	"errors"

	records "github.com/domabas/domabas/backend/internal/data/email/models"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailSource interface {
	List(context.Context, m.EmailActor, int, string) ([]records.EmailProviderRecord, string, error)
	Get(context.Context, m.EmailActor, string) (records.EmailProviderRecord, error)
	Create(context.Context, m.EmailActor, records.EmailProviderWrite) (records.EmailProviderRecord, error)
	Update(context.Context, m.EmailActor, records.EmailProviderWrite) (records.EmailProviderRecord, error)
	Delete(context.Context, m.EmailActor, string, int64) error
	BeginTest(context.Context, m.EmailActor, m.EmailTestAdmission) (string, error)
	EndTest(context.Context, m.EmailActor, string) error
	RotationCandidates(context.Context, string, int) ([]records.EmailProviderRecord, error)
	Rotate(context.Context, records.EmailProviderRecord, string, []byte) error
	Runs(context.Context, m.EmailActor, m.EmailRunQuery) (m.EmailRunPage, error)
	Run(context.Context, m.EmailActor, string) (m.EmailRun, error)
	Start(context.Context, m.EmailActor, string, m.EmailStartCommand) (m.EmailRun, error)
	RequestedRun(context.Context, m.EmailActor, string, m.EmailStartRun) (*m.EmailRun, error)
}
type EmailRepository struct {
	source EmailSource
	vault  p.EmailCredentialVault
}

func NewEmailRepository(source EmailSource, vault p.EmailCredentialVault) *EmailRepository {
	return &EmailRepository{source: source, vault: vault}
}

func (r *EmailRepository) List(ctx context.Context, a m.EmailActor, limit int, cursor string) (m.EmailProviderPage, error) {
	records, next, err := r.source.List(ctx, a, limit, cursor)
	result := m.EmailProviderPage{Items: []m.EmailProvider{}, NextCursor: next}
	for _, record := range records {
		result.Items = append(result.Items, r.emailProviderRecordToDomainMapper(record))
	}
	return result, err
}
func (r *EmailRepository) Get(ctx context.Context, a m.EmailActor, id string) (m.EmailProvider, error) {
	record, err := r.source.Get(ctx, a, id)
	if err != nil {
		return m.EmailProvider{}, err
	}
	return r.emailProviderRecordToDomainMapper(record), nil
}
func (r *EmailRepository) Create(ctx context.Context, a m.EmailActor, input m.EmailProviderInput) (m.EmailProvider, error) {
	if !r.vault.Available() {
		return m.EmailProvider{}, m.ErrUnavailable
	}
	if input.Username == nil || input.Password == nil {
		return m.EmailProvider{}, m.EmailValidationError{Message: "username and password are required"}
	}
	credentials := m.EmailCredentials{Username: *input.Username, Password: *input.Password}
	if err := credentials.Validate(); err != nil {
		return m.EmailProvider{}, err
	}
	key, ciphertext, err := r.vault.Seal(m.EmailCredentialIdentity{ProviderID: input.ID, AccountID: a.AccountID, OwnerID: a.UserID}, credentials)
	if err != nil {
		return m.EmailProvider{}, m.ErrUnavailable
	}
	record, err := r.source.Create(ctx, a, records.EmailProviderWrite{Input: records.EmailProviderInput{ID: input.ID, MaximumProviders: input.MaximumProviders, EmailSettings: records.EmailSettings(input.EmailSettings), Username: input.Username, Password: input.Password, ExpectedRevision: input.ExpectedRevision, RenewConsent: input.RenewConsent}, KeyID: key, Ciphertext: ciphertext})
	if err != nil {
		return m.EmailProvider{}, err
	}
	return r.emailProviderRecordToDomainMapper(record), nil
}
func (r *EmailRepository) UpdateFacts(ctx context.Context, a m.EmailActor, id string) (m.EmailProviderUpdateFacts, error) {
	record, err := r.source.Get(ctx, a, id)
	if err != nil {
		return m.EmailProviderUpdateFacts{}, err
	}
	credentials, openErr := r.vault.Open(emailCredentialIdentityMapper(record), record.KeyID, record.Ciphertext)
	return m.EmailProviderUpdateFacts{Provider: emailProviderValueToDomainMapper(record.Provider), Credentials: credentials, CredentialsAvailable: openErr == nil, VaultAvailable: r.vault.Available()}, nil
}
func (r *EmailRepository) Update(ctx context.Context, a m.EmailActor, command m.EmailProviderUpdateCommand) (m.EmailProvider, error) {
	input := command.Input
	write := records.EmailProviderWrite{Input: records.EmailProviderInput{ID: input.ID, EmailSettings: records.EmailSettings(input.EmailSettings)}, SnapshotCredentialVersion: command.Expected.CredentialVersion, SnapshotProviderRevision: command.Expected.Revision, SnapshotConsentRevision: command.Expected.ConsentRevision, CredentialChanged: command.CredentialChanged, SourceChanged: command.SourceChanged, RenewConsent: command.RenewConsent, Noop: command.Noop, SupersededState: command.SupersededState, SupersededCode: command.SupersededCode}
	if command.CredentialChanged {
		key, ciphertext, err := r.vault.Seal(m.EmailCredentialIdentity{ProviderID: input.ID, AccountID: a.AccountID, OwnerID: a.UserID}, command.Credentials)
		if err != nil {
			return m.EmailProvider{}, m.ErrUnavailable
		}
		write.KeyID, write.Ciphertext = key, ciphertext
	}
	record, err := r.source.Update(ctx, a, write)
	if err != nil {
		return m.EmailProvider{}, err
	}
	return r.emailProviderRecordToDomainMapper(record), nil
}
func (r *EmailRepository) Delete(ctx context.Context, a m.EmailActor, id string, revision int64) error {
	return r.source.Delete(ctx, a, id, revision)
}
func (r *EmailRepository) BeginTest(ctx context.Context, a m.EmailActor, admission m.EmailTestAdmission) (string, error) {
	if !r.vault.Available() {
		return "", m.ErrUnavailable
	}
	return r.source.BeginTest(ctx, a, admission)
}
func (r *EmailRepository) EndTest(ctx context.Context, a m.EmailActor, token string) error {
	return r.source.EndTest(ctx, a, token)
}
func (r *EmailRepository) TestCredentials(ctx context.Context, a m.EmailActor, input m.EmailTestConnection) (m.EmailConnection, error) {
	result := input.EmailConnection
	if input.ProviderID != "" {
		record, err := r.source.Get(ctx, a, input.ProviderID)
		if err != nil {
			return result, err
		}
		if input.ExpectedRevision == nil || *input.ExpectedRevision != record.Provider.Revision {
			return result, m.ErrConflict
		}
		credentials, err := r.vault.Open(emailCredentialIdentityMapper(record), record.KeyID, record.Ciphertext)
		if err != nil && (input.Username == nil || input.Password == nil) {
			return result, m.ErrUnavailable
		}
		result.Credentials = credentials
	}
	if input.Username != nil {
		result.Credentials.Username = *input.Username
	}
	if input.Password != nil {
		result.Credentials.Password = *input.Password
	}
	if err := result.Credentials.Validate(); err != nil {
		return result, err
	}
	return result, nil
}
func (r *EmailRepository) VerifyTest(ctx context.Context, a m.EmailActor, input m.EmailTestConnection) error {
	if input.ProviderID == "" {
		_, _, err := r.source.List(ctx, a, 1, "")
		return err
	}
	record, err := r.source.Get(ctx, a, input.ProviderID)
	if err != nil {
		return err
	}
	if input.ExpectedRevision == nil || *input.ExpectedRevision != record.Provider.Revision {
		return m.ErrConflict
	}
	return nil
}
func (r *EmailRepository) Rotate(ctx context.Context, limit int) error {
	if !r.vault.Available() {
		return nil
	}
	records, err := r.source.RotationCandidates(ctx, r.vault.ActiveID(), limit)
	if err != nil {
		return err
	}
	failures := []error{}
	for _, record := range records {
		credentials, err := r.vault.Open(emailCredentialIdentityMapper(record), record.KeyID, record.Ciphertext)
		if err != nil {
			continue
		}
		key, ciphertext, err := r.vault.Seal(emailCredentialIdentityMapper(record), credentials)
		if err == nil {
			err = r.source.Rotate(ctx, record, key, ciphertext)
		}
		failures = append(failures, err)
	}
	return errors.Join(failures...)
}
func (r *EmailRepository) Runs(ctx context.Context, a m.EmailActor, q m.EmailRunQuery) (m.EmailRunPage, error) {
	return r.source.Runs(ctx, a, q)
}
func (r *EmailRepository) Run(ctx context.Context, a m.EmailActor, id string) (m.EmailRun, error) {
	return r.source.Run(ctx, a, id)
}
func (r *EmailRepository) RequestedRun(ctx context.Context, a m.EmailActor, id string, input m.EmailStartRun) (*m.EmailRun, error) {
	return r.source.RequestedRun(ctx, a, id, input)
}
func (r *EmailRepository) Start(ctx context.Context, a m.EmailActor, id string, command m.EmailStartCommand) (m.EmailRun, error) {
	return r.source.Start(ctx, a, id, command)
}
