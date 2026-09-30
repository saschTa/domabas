package repos

import (
	records "github.com/domabas/domabas/backend/internal/data/email/models"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func emailCredentialIdentityMapper(record records.EmailProviderRecord) m.EmailCredentialIdentity {
	return m.EmailCredentialIdentity{ProviderID: record.Provider.ID, OwnerID: record.Provider.OwnerID, AccountID: record.Provider.AccountID}
}

func (r *EmailRepository) emailProviderRecordToDomainMapper(record records.EmailProviderRecord) m.EmailProvider {
	result := emailProviderValueToDomainMapper(record.Provider)
	credentials, err := r.vault.Open(emailCredentialIdentityMapper(record), record.KeyID, record.Ciphertext)
	if err != nil {
		result.CredentialState = "missing_key"
		if !r.vault.Available() {
			result.CredentialState = "unavailable"
		}
	} else {
		result.Username = credentials.Username
		result.CredentialState = "ready"
	}
	return result
}
