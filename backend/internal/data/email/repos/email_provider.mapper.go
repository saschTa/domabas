package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/email/models"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func emailProviderValueToDomainMapper(p r.EmailProvider) m.EmailProvider {
	return m.EmailProvider{ID: p.ID, OwnerID: p.OwnerID, AccountID: p.AccountID, EmailSettings: m.EmailSettings(p.EmailSettings), Revision: p.Revision, SourceGeneration: p.SourceGeneration, CredentialVersion: p.CredentialVersion, ConsentRevision: p.ConsentRevision, ConsentState: p.ConsentState, CredentialState: p.CredentialState, Username: p.Username, LastFailureCode: p.LastFailureCode, HasPassword: p.HasPassword, NextPollAt: p.NextPollAt, LastRunID: p.LastRunID, LastRunStatus: p.LastRunStatus, ActiveRunID: p.ActiveRunID, LastAttemptAt: p.LastAttemptAt, CreatedAt: p.CreatedAt, UpdatedAt: p.UpdatedAt}
}
