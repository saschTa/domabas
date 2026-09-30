package models

import "time"

type PersonalActivityItem struct {
	ID, Kind, NamespaceID, NamespaceName, Status string
	Stage, DocumentID, ProviderID, BatchID       *string
	Title, FailureCode                           *string
	CreatedAt                                    time.Time
	StartedAt, FinishedAt                        *time.Time
	CanOpen                                      bool
}

type PersonalActivity struct {
	Active, Finished                     []PersonalActivityItem
	ActiveTruncated                      bool
	ActiveNextCursor, FinishedNextCursor string
	GeneratedAt                          time.Time
}

type IdentityActivityPageRequest struct {
	ActiveCursor, FinishedCursor string
	Scope                        IdentityActivityScope
}

type IdentityActivityScope struct {
	Documents, Email, Batches, Titles []string
}

type IdentityActivityMembership struct {
	AccountID      string
	Role           IdentityRole
	Owner, Enabled bool
	Claims         []IdentityPermission
}
