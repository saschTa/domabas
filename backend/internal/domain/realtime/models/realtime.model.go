package models

import identity "github.com/domabas/domabas/backend/internal/domain/identity/models"

type RealtimeSubject struct {
	UserID, AccountID, SessionDigest string
	CredentialRevision               int64
}

type RealtimeSignal struct{ Kind, AccountID, UserID string }

type RealtimeMembership struct {
	AccountID, Role string
	Owner           bool
	Claims          []string
	Enabled         bool
}

type RealtimeSnapshot struct {
	Identity    identity.IdentityAuthorityFacts
	SystemRole  string
	Memberships []RealtimeMembership
	MemberUsers map[string]bool
}

type RealtimeTopic string

const (
	Documents     RealtimeTopic = "documents"
	Processing    RealtimeTopic = "processing"
	Configuration RealtimeTopic = "processing_configuration"
	Email         RealtimeTopic = "email"
	Paperless     RealtimeTopic = "paperless"
	Chat          RealtimeTopic = "chat"
	Activity      RealtimeTopic = "activity"
	Identity      RealtimeTopic = "identity"
	Members       RealtimeTopic = "members"
	SystemUsers   RealtimeTopic = "system_users"
)
