package models

import "time"

type RealtimeIdentityRecord struct {
	UserID, AccountID, SessionDigest string
	CredentialRevision               int64
	MustChangePassword               bool
	SessionExpiresAt                 *time.Time
}

type RealtimeAuthorityRecord struct {
	Principal                 RealtimeIdentityRecord
	MembershipEnabled         bool
	SessionAccountID          string
	SessionUserID             string
	SessionCredentialRevision int64
	ObservedAt                time.Time
}

type RealtimeSubject struct {
	UserID, AccountID, SessionDigest string
	CredentialRevision               int64
}
type RealtimeMembership struct {
	AccountID, Role string
	Owner           bool
	Claims          []string
	Enabled         bool
}
type RealtimeSnapshot struct {
	Identity    RealtimeAuthorityRecord
	SystemRole  string
	Memberships []RealtimeMembership
	MemberUsers map[string]bool
}
type RealtimeSignal struct {
	Version   int    `json:"version"`
	Schema    string `json:"schema"`
	Kind      string `json:"kind"`
	AccountID string `json:"account,omitempty"`
	UserID    string `json:"user,omitempty"`
}
