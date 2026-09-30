package handlers

import (
	"context"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type IdentityService interface {
	Register(context.Context, string, string, string) (domain.IdentitySession, error)
	Login(context.Context, string, string) (domain.IdentitySession, error)
	RestoreSession(context.Context, string) (domain.IdentitySession, error)
	Logout(context.Context, domain.IdentityPrincipal) error
	ChangePassword(context.Context, domain.IdentityPrincipal, string, string) error
	CreateMember(context.Context, domain.IdentityPrincipal, string, string, domain.IdentityRole, []domain.IdentityPermission) (domain.IdentityMember, error)
	UpdateMember(context.Context, domain.IdentityPrincipal, string, domain.IdentityRole, []domain.IdentityPermission, bool) (domain.IdentityMember, error)
	ListMembers(context.Context, domain.IdentityPrincipal, int, int) (domain.IdentityMemberPage, error)
	ListAccounts(context.Context, domain.IdentityPrincipal, int, int) (domain.IdentityMembershipPage, error)
	SwitchAccount(context.Context, domain.IdentityPrincipal, string) (domain.IdentitySession, error)
	CreateInvitation(context.Context, domain.IdentityPrincipal, string, domain.IdentityRole, []domain.IdentityPermission) (domain.IdentityIssuedInvitation, error)
	ListInvitations(context.Context, domain.IdentityPrincipal, int, int) (domain.IdentityInvitationPage, error)
	RevokeInvitation(context.Context, domain.IdentityPrincipal, string) error
	AcceptInvitation(context.Context, domain.IdentityPrincipal, string) (domain.IdentityMembership, error)
	ListSystemUsers(context.Context, domain.IdentityPrincipal, int, int) (domain.SystemUserPage, error)
	UpdateSystemUser(context.Context, domain.IdentityPrincipal, string, domain.IdentityRole) (domain.SystemUser, error)
}
