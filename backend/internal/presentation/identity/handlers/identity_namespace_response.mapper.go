package handlers

import (
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func identityPermissionStringsMapper(values []domain.IdentityPermission) []string {
	result := make([]string, len(values))
	for i, v := range values {
		result[i] = string(v)
	}
	return result
}

func identityPermissionsMapper(values []string) []domain.IdentityPermission {
	result := make([]domain.IdentityPermission, len(values))
	for i, v := range values {
		result[i] = domain.IdentityPermission(v)
	}
	return result
}

func identityMembershipResponseMapper(m domain.IdentityMembership) contract.AccountMembership {
	return contract.AccountMembership{Account: contract.AccountIdentity{Id: uuid.MustParse(m.AccountID), Name: m.AccountName}, Role: contract.AccountRole(m.Role), IsOwner: m.IsOwner, Claims: identityPermissionStringsMapper(m.Claims), Permissions: identityPermissionStringsMapper(m.Permissions)}
}

func identityInvitationResponseMapper(i domain.IdentityInvitation) contract.Invitation {
	status := contract.InvitationStatusPending
	if i.AcceptedAt != nil {
		status = contract.InvitationStatusAccepted
	} else if i.RevokedAt != nil {
		status = contract.InvitationStatusRevoked
	} else if !i.ExpiresAt.After(time.Now()) {
		status = contract.InvitationStatusExpired
	}
	return contract.Invitation{Id: uuid.MustParse(i.ID), Email: i.Email, Role: contract.AccountRole(i.Role), Claims: identityPermissionStringsMapper(i.Claims), CreatedAt: i.CreatedAt, ExpiresAt: i.ExpiresAt, Status: status}
}

func identitySystemUserResponseMapper(u domain.SystemUser) contract.SystemUser {
	return contract.SystemUser{Id: uuid.MustParse(u.ID), Email: u.Email, Role: contract.SystemRole(u.Role), CreatedAt: u.CreatedAt}
}
