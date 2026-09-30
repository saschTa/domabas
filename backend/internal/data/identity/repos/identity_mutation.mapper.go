package repos

import (
	records "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func identityBackgroundFactsMapper(f domain.IdentityAuthorityFacts) (records.IdentityRecord, error) {
	p := f.Principal
	p.SessionDigest = "background-facts"
	r, err := identityPrincipalDomainToRecordMapper(p)
	r.Membership.Enabled = f.MembershipEnabled
	r.Session = model.Sessions{}
	return r, err
}

func identityInvitationFactsMapper(f domain.IdentityInvitationFacts) (records.IdentityInvitationFactsRecord, error) {
	v := f.Invitation
	id, e1 := uuid.Parse(v.ID)
	account, e2 := uuid.Parse(v.AccountID)
	issuer, e3 := uuid.Parse(v.IssuerID)
	if e1 != nil || e2 != nil || e3 != nil {
		return records.IdentityInvitationFactsRecord{}, domain.ErrNotFound
	}
	i, err := identityBackgroundFactsMapper(f.Issuer)
	if err != nil {
		return records.IdentityInvitationFactsRecord{}, err
	}
	return records.IdentityInvitationFactsRecord{Invitation: model.Invitations{ID: id, AccountID: account, IssuerID: issuer, Email: v.Email, Role: string(v.Role), Claims: identityClaimStringsMapper(v.Claims), Digest: v.Digest, CreatedAt: v.CreatedAt, ExpiresAt: v.ExpiresAt, AcceptedAt: v.AcceptedAt, RevokedAt: v.RevokedAt}, Issuer: i, AlreadyMember: f.AlreadyMember}, nil
}

func identitySystemUserFactsMapper(f domain.IdentitySystemUserFacts) (records.IdentitySystemUserFactsRecord, error) {
	id, err := uuid.Parse(f.Target.ID)
	if err != nil {
		return records.IdentitySystemUserFactsRecord{}, domain.ErrNotFound
	}
	return records.IdentitySystemUserFactsRecord{Target: model.Users{ID: id, Email: f.Target.Email, SystemRole: string(f.Target.Role), CreatedAt: f.Target.CreatedAt}, Installation: records.IdentityInstallationRecord{BootstrapEligible: f.Installation.BootstrapEligible, AdministratorIDs: f.Installation.AdministratorIDs}}, nil
}
