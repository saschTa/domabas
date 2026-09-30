package models

import "github.com/domabas/domabas/backend/internal/data/postgres/generated/model"

type IdentityRecord struct {
	Account               model.Accounts
	User                  model.Users
	Membership            model.Memberships
	PersonalMembership    model.Memberships
	Session               model.Sessions
	ExpectedSetupEligible bool
	ConsumeSetup          bool
}

type IdentityInstallationRecord struct {
	BootstrapEligible bool
	AdministratorIDs  []string
}

type IdentitySystemUserFactsRecord struct {
	Target       model.Users
	Installation IdentityInstallationRecord
}

type IdentityInvitationFactsRecord struct {
	Invitation    model.Invitations
	Issuer        IdentityRecord
	AlreadyMember bool
}
type IdentityMemberRecords struct {
	Items []IdentityRecord
	Total int64
}
type IdentityInvitationRecords struct {
	Items []model.Invitations
	Total int64
}
type IdentityUserRecords struct {
	Items      []model.Users
	Total      int64
	AdminCount int64
}
