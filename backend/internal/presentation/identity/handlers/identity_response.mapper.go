package handlers

import (
	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func identityResponseMapper(p domain.IdentityPrincipal) contract.CurrentIdentity {
	permissions := make([]contract.Permission, 0, len(p.Permissions))
	for _, permission := range p.Permissions {
		permissions = append(permissions, contract.Permission(permission))
	}
	return contract.CurrentIdentity{Account: contract.AccountIdentity{Id: uuid.MustParse(p.AccountID), Name: p.AccountName}, User: contract.UserIdentity{Id: uuid.MustParse(p.UserID), Email: p.Email, MustChangePassword: p.MustChangePassword}, Role: contract.AccountRole(p.Role), Permissions: permissions, Claims: identityPermissionStringsMapper(p.Claims), IsOwner: p.IsOwner, SystemRole: contract.SystemRole(p.SystemRole)}
}

func identitySessionResponseMapper(s domain.IdentitySession) contract.AuthSession {
	return contract.AuthSession{Token: s.Token, ExpiresAt: s.ExpiresAt, Identity: identityResponseMapper(s.Identity)}
}

func identityMemberResponseMapper(m domain.IdentityMember) contract.AccountUser {
	return contract.AccountUser{Id: uuid.MustParse(m.ID), Email: m.Email, Role: contract.AccountRole(m.Role), Enabled: m.Enabled, MustChangePassword: m.MustChangePassword, IsOwner: m.IsOwner, Claims: identityPermissionStringsMapper(m.Claims), Permissions: identityPermissionStringsMapper(m.Permissions)}
}
