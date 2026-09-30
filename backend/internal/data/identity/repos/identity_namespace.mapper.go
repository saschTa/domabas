package repos

import (
	records "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

func identityPermissionsMapper(values []string) []domain.IdentityPermission {
	result := make([]domain.IdentityPermission, len(values))
	for i, v := range values {
		result[i] = domain.IdentityPermission(v)
	}
	return result
}

func identityClaimStringsMapper(values []domain.IdentityPermission) []string {
	result := make([]string, len(values))
	for i, v := range values {
		result[i] = string(v)
	}
	return result
}

func identityMembershipRecordToDomainMapper(r records.IdentityRecord) domain.IdentityMembership {
	return domain.IdentityMembership{AccountID: r.Account.ID.String(), AccountName: r.Account.Name, Role: domain.IdentityRole(r.Membership.Role), IsOwner: r.Membership.IsOwner, Claims: identityPermissionsMapper(r.Membership.Claims)}
}

func identityInvitationRecordToDomainMapper(r model.Invitations) domain.IdentityInvitation {
	return domain.IdentityInvitation{ID: r.ID.String(), AccountID: r.AccountID.String(), IssuerID: r.IssuerID.String(), Email: r.Email, Role: domain.IdentityRole(r.Role), Claims: identityPermissionsMapper(r.Claims), CreatedAt: r.CreatedAt, ExpiresAt: r.ExpiresAt, AcceptedAt: r.AcceptedAt, RevokedAt: r.RevokedAt}
}

func identitySystemUserRecordToDomainMapper(r model.Users) domain.SystemUser {
	return domain.SystemUser{ID: r.ID.String(), Email: r.Email, Role: domain.IdentityRole(r.SystemRole), CreatedAt: r.CreatedAt}
}
