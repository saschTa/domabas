package models

type IdentityInstallationFacts struct {
	BootstrapEligible bool
	AdministratorIDs  []string
}

type IdentitySystemUserFacts struct {
	Target       SystemUser
	Installation IdentityInstallationFacts
}

type IdentityInvitationFacts struct {
	Invitation    IdentityInvitation
	Issuer        IdentityAuthorityFacts
	AlreadyMember bool
}
