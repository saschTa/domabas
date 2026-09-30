package repos

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func (repo *IdentityRepository) Invitation(ctx context.Context, accountID, id string) (m.IdentityInvitation, error) {
	account, e1 := uuid.Parse(accountID)
	invitation, e2 := uuid.Parse(id)
	if e1 != nil || e2 != nil {
		return m.IdentityInvitation{}, m.ErrNotFound
	}
	record, err := repo.source.IdentityInvitation(ctx, account, invitation)
	return identityInvitationRecordToDomainMapper(record), identityError(err)
}

func (repo *IdentityRepository) InstallationFacts(ctx context.Context) (m.IdentityInstallationFacts, error) {
	f, err := repo.source.IdentityInstallationFacts(ctx)
	return m.IdentityInstallationFacts{BootstrapEligible: f.BootstrapEligible, AdministratorIDs: f.AdministratorIDs}, identityError(err)
}

func (repo *IdentityRepository) MemberFacts(ctx context.Context, accountID, userID string) (m.IdentityMember, error) {
	account, e1 := uuid.Parse(accountID)
	user, e2 := uuid.Parse(userID)
	if e1 != nil || e2 != nil {
		return m.IdentityMember{}, m.ErrNotFound
	}
	f, err := repo.source.IdentityMemberFacts(ctx, account, user)
	return identityMemberRecordToDomainMapper(f), identityError(err)
}

func (repo *IdentityRepository) SystemUserFacts(ctx context.Context, userID string) (m.IdentitySystemUserFacts, error) {
	id, err := uuid.Parse(userID)
	if err != nil {
		return m.IdentitySystemUserFacts{}, m.ErrNotFound
	}
	f, err := repo.source.IdentitySystemUserFacts(ctx, id)
	return m.IdentitySystemUserFacts{Target: identitySystemUserRecordToDomainMapper(f.Target), Installation: m.IdentityInstallationFacts{BootstrapEligible: f.Installation.BootstrapEligible, AdministratorIDs: f.Installation.AdministratorIDs}}, identityError(err)
}

func (repo *IdentityRepository) InvitationFacts(ctx context.Context, digest, userID string) (m.IdentityInvitationFacts, error) {
	id, err := uuid.Parse(userID)
	if err != nil {
		return m.IdentityInvitationFacts{}, m.ErrNotFound
	}
	f, err := repo.source.IdentityInvitationFacts(ctx, digest, id)
	invitation := identityInvitationRecordToDomainMapper(f.Invitation)
	invitation.Digest = f.Invitation.Digest
	return m.IdentityInvitationFacts{Invitation: invitation, Issuer: m.IdentityAuthorityFacts{Principal: identityPrincipalRecordToDomainMapper(f.Issuer), MembershipEnabled: f.Issuer.Membership.Enabled}, AlreadyMember: f.AlreadyMember}, identityError(err)
}

func (repo *IdentityRepository) BootstrapAdministrator(ctx context.Context, facts m.IdentitySystemUserFacts) error {
	record, err := identitySystemUserFactsMapper(facts)
	if err != nil {
		return err
	}
	return identityError(repo.source.BootstrapAdministrator(ctx, record))
}
