package models

import "time"

type EmailProviderRecord struct {
	Provider                  EmailProvider
	KeyID                     string
	Ciphertext                []byte
	CurrentCredentialRevision int64
}
type EmailProviderWrite struct {
	Input                                             EmailProviderInput
	KeyID                                             string
	Ciphertext                                        []byte
	CredentialChanged, UsernameChanged                bool
	SnapshotCredentialVersion                         int64
	SnapshotProviderRevision, SnapshotConsentRevision int64
	RenewConsent, SourceChanged, Noop                 bool
	SupersededState, SupersededCode                   string
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
