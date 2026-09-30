package repos

import (
	"context"
	"time"

	identityrecords "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	"github.com/google/uuid"
)

type IdentitySource interface {
	IdentitySessionAuthority(context.Context, string) (identityrecords.IdentityRecord, time.Time, error)
	IdentityBackgroundAuthority(context.Context, uuid.UUID, uuid.UUID) (identityrecords.IdentityRecord, error)
	IdentityInstallationFacts(context.Context) (identityrecords.IdentityInstallationRecord, error)
	IdentityMemberFacts(context.Context, uuid.UUID, uuid.UUID) (identityrecords.IdentityRecord, error)
	IdentitySystemUserFacts(context.Context, uuid.UUID) (identityrecords.IdentitySystemUserFactsRecord, error)
	IdentityInvitationFacts(context.Context, string, uuid.UUID) (identityrecords.IdentityInvitationFactsRecord, error)
	IdentityInvitation(context.Context, uuid.UUID, uuid.UUID) (model.Invitations, error)
	BootstrapAdministrator(context.Context, identityrecords.IdentitySystemUserFactsRecord) error
	RegisterIdentity(context.Context, identityrecords.IdentityRecord) (identityrecords.IdentityRecord, error)
	IdentityCredentials(context.Context, string) (identityrecords.IdentityRecord, error)
	CreateIdentitySession(context.Context, identityrecords.IdentityRecord, model.Sessions) (identityrecords.IdentityRecord, error)
	LogoutIdentity(context.Context, identityrecords.IdentityRecord) error
	ChangeIdentityPassword(context.Context, identityrecords.IdentityRecord, identityrecords.IdentityRecord, string) error
	CreateIdentityMember(context.Context, identityrecords.IdentityRecord, identityrecords.IdentityRecord) (identityrecords.IdentityRecord, error)
	UpdateIdentityMember(context.Context, identityrecords.IdentityRecord, identityrecords.IdentityRecord, string, []string, bool) (identityrecords.IdentityRecord, error)
	ListIdentityMembers(context.Context, identityrecords.IdentityRecord, int, int) (identityrecords.IdentityMemberRecords, error)
	CleanupIdentitySessions(context.Context, time.Time) error
	ListIdentityAccounts(context.Context, identityrecords.IdentityRecord, int, int) (identityrecords.IdentityMemberRecords, error)
	SwitchIdentityAccount(context.Context, identityrecords.IdentityRecord, identityrecords.IdentityRecord, model.Sessions) (identityrecords.IdentityRecord, error)
	CreateIdentityInvitation(context.Context, identityrecords.IdentityRecord, model.Invitations) (model.Invitations, error)
	ListIdentityInvitations(context.Context, identityrecords.IdentityRecord, int, int) (identityrecords.IdentityInvitationRecords, error)
	RevokeIdentityInvitation(context.Context, identityrecords.IdentityRecord, model.Invitations, time.Time) error
	AcceptIdentityInvitation(context.Context, identityrecords.IdentityRecord, identityrecords.IdentityInvitationFactsRecord) (identityrecords.IdentityRecord, error)
	ListIdentitySystemUsers(context.Context, identityrecords.IdentityRecord, int, int) (identityrecords.IdentityUserRecords, error)
	UpdateIdentitySystemUser(context.Context, identityrecords.IdentityRecord, identityrecords.IdentitySystemUserFactsRecord, string) (model.Users, error)
}
