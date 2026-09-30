package models

import "time"

type IdentityAuthorityFacts struct {
	Principal                 IdentityPrincipal
	MembershipEnabled         bool
	SessionAccountID          string
	SessionUserID             string
	SessionCredentialRevision int64
	ObservedAt                time.Time
}

func (p IdentityPrincipal) HasPermission(permission IdentityPermission) bool {
	if p.MustChangePassword {
		return false
	}
	for _, allowed := range p.Permissions {
		if allowed == permission {
			return true
		}
	}
	return false
}

func (f IdentityAuthorityFacts) ValidateSession(digest string) error {
	p := f.Principal
	if digest == "" || p.SessionDigest != digest || p.UserID == "" || p.AccountID == "" ||
		f.SessionAccountID != p.AccountID || f.SessionUserID != p.UserID || p.CredentialRevision <= 0 ||
		f.SessionCredentialRevision != p.CredentialRevision || (p.SessionExpiresAt != nil && !p.SessionExpiresAt.After(f.ObservedAt)) {
		return ErrUnauthorized
	}
	if !f.MembershipEnabled {
		return ErrMembershipDisabled
	}
	return nil
}
