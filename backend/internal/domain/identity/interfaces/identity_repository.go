package interfaces

import (
	"context"
	"time"

	identitymodels "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type IdentityRepository interface {
	SessionAuthority(context.Context, string) (identitymodels.IdentityAuthorityFacts, error)
	BackgroundAuthority(context.Context, string, string) (identitymodels.IdentityAuthorityFacts, error)
	InstallationFacts(context.Context) (identitymodels.IdentityInstallationFacts, error)
	MemberFacts(context.Context, string, string) (identitymodels.IdentityMember, error)
	SystemUserFacts(context.Context, string) (identitymodels.IdentitySystemUserFacts, error)
	InvitationFacts(context.Context, string, string) (identitymodels.IdentityInvitationFacts, error)
	Invitation(context.Context, string, string) (identitymodels.IdentityInvitation, error)
	BootstrapAdministrator(context.Context, identitymodels.IdentitySystemUserFacts) error
	Register(context.Context, identitymodels.IdentityRegistration) (identitymodels.IdentityPrincipal, error)
	CredentialsByEmail(context.Context, string) (identitymodels.IdentityCredentials, error)
	CreateSession(context.Context, identitymodels.IdentityCredentials, identitymodels.IdentitySessionRecord) (identitymodels.IdentityPrincipal, error)
	Logout(context.Context, identitymodels.IdentityPrincipal) error
	ChangePassword(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityCredentials, string, time.Time) error
	CreateMember(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityNewMember, time.Time) (identitymodels.IdentityMember, error)
	UpdateMember(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityMember, identitymodels.IdentityRole, []identitymodels.IdentityPermission, bool, time.Time) (identitymodels.IdentityMember, error)
	ListMembers(context.Context, identitymodels.IdentityPrincipal, int, int, time.Time) (identitymodels.IdentityMemberPage, error)
	CleanupSessions(context.Context, time.Time) error
	ListAccounts(context.Context, identitymodels.IdentityPrincipal, int, int) (identitymodels.IdentityMembershipPage, error)
	SwitchAccount(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityAuthorityFacts, identitymodels.IdentitySessionRecord) (identitymodels.IdentityPrincipal, *time.Time, error)
	CreateInvitation(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityInvitation) (identitymodels.IdentityInvitation, error)
	ListInvitations(context.Context, identitymodels.IdentityPrincipal, int, int) (identitymodels.IdentityInvitationPage, error)
	RevokeInvitation(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityInvitation, time.Time) error
	AcceptInvitation(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentityInvitationFacts) (identitymodels.IdentityMembership, error)
	ListSystemUsers(context.Context, identitymodels.IdentityPrincipal, int, int) (identitymodels.SystemUserPage, error)
	UpdateSystemUser(context.Context, identitymodels.IdentityPrincipal, identitymodels.IdentitySystemUserFacts, identitymodels.IdentityRole) (identitymodels.SystemUser, error)
}
