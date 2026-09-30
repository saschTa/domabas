package models

type IdentityRegistrationRequest struct{ AccountName, Email, Password string }
type IdentityLoginRequest struct{ Email, Password string }
type IdentityPasswordRequest struct{ CurrentPassword, NewPassword string }
type IdentityCreateMemberRequest struct {
	Email, Password, Role string
	Claims                []string
}
type IdentityUpdateMemberRequest struct {
	Role    string
	Enabled bool
	Claims  []string
}
type IdentityInvitationRequest struct {
	Email, Role string
	Claims      []string
}
type IdentityAcceptInvitationRequest struct{ Code string }
type IdentitySwitchAccountRequest struct{ AccountID string }
type IdentitySystemRoleRequest struct{ Role string }
