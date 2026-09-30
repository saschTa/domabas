package repos

import (
	identityrecords "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func identityPrincipalRecordToDomainMapper(r identityrecords.IdentityRecord) identitymodels.IdentityPrincipal {
	return identitymodels.IdentityPrincipal{UserID: r.User.ID.String(), Email: r.User.Email, AccountID: r.Account.ID.String(), AccountName: r.Account.Name, SessionDigest: r.Session.Digest, Role: identitymodels.IdentityRole(r.Membership.Role), SystemRole: identitymodels.IdentityRole(r.User.SystemRole), IsOwner: r.Membership.IsOwner, Claims: identityPermissionsMapper(r.Membership.Claims), MustChangePassword: r.User.MustChangePassword, CredentialRevision: r.User.CredentialRevision, SessionExpiresAt: r.Session.ExpiresAt}
}

func identityPrincipalDomainToRecordMapper(p identitymodels.IdentityPrincipal) (identityrecords.IdentityRecord, error) {
	account, e1 := uuid.Parse(p.AccountID)
	user, e2 := uuid.Parse(p.UserID)
	if e1 != nil || e2 != nil || p.SessionDigest == "" {
		return identityrecords.IdentityRecord{}, identitymodels.ErrUnauthorized
	}
	return identityrecords.IdentityRecord{Account: model.Accounts{ID: account}, User: model.Users{ID: user, Email: p.Email, CredentialRevision: p.CredentialRevision, SystemRole: string(p.SystemRole), MustChangePassword: p.MustChangePassword}, Membership: model.Memberships{AccountID: account, UserID: user, Role: string(p.Role), IsOwner: p.IsOwner, Enabled: true, Claims: identityClaimStringsMapper(p.Claims)}, Session: model.Sessions{Digest: p.SessionDigest, AccountID: account, UserID: user, CredentialRevision: p.CredentialRevision, ExpiresAt: p.SessionExpiresAt}}, nil
}

func identityMemberRecordToDomainMapper(r identityrecords.IdentityRecord) identitymodels.IdentityMember {
	return identitymodels.IdentityMember{ID: r.User.ID.String(), Email: r.User.Email, Role: identitymodels.IdentityRole(r.Membership.Role), IsOwner: r.Membership.IsOwner, Claims: identityPermissionsMapper(r.Membership.Claims), Enabled: r.Membership.Enabled, MustChangePassword: r.User.MustChangePassword}
}
