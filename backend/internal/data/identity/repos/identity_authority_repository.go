package repos

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func (r *IdentityRepository) SessionAuthority(ctx context.Context, digest string) (m.IdentityAuthorityFacts, error) {
	record, observed, err := r.source.IdentitySessionAuthority(ctx, digest)
	return m.IdentityAuthorityFacts{Principal: identityPrincipalRecordToDomainMapper(record), MembershipEnabled: record.Membership.Enabled,
		SessionAccountID: record.Session.AccountID.String(), SessionUserID: record.Session.UserID.String(), SessionCredentialRevision: record.Session.CredentialRevision, ObservedAt: observed}, identityError(err)
}

func (r *IdentityRepository) BackgroundAuthority(ctx context.Context, accountID, userID string) (m.IdentityAuthorityFacts, error) {
	account, e1 := uuid.Parse(accountID)
	user, e2 := uuid.Parse(userID)
	if e1 != nil || e2 != nil {
		return m.IdentityAuthorityFacts{}, m.ErrNotFound
	}
	record, err := r.source.IdentityBackgroundAuthority(ctx, account, user)
	return m.IdentityAuthorityFacts{Principal: identityPrincipalRecordToDomainMapper(record), MembershipEnabled: record.Membership.Enabled}, identityError(err)
}
