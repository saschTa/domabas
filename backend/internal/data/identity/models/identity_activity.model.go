package models

import (
	"time"

	"github.com/google/uuid"
)

type IdentityActivityRecord struct {
	ID, NamespaceID                 uuid.UUID
	Kind, NamespaceName, Status     string
	Stage, Title, FailureCode       *string
	DocumentID, ProviderID, BatchID *uuid.UUID
	CreatedAt                       time.Time
	StartedAt, FinishedAt           *time.Time
	CanOpen                         bool
}

type IdentityActivityRecords struct {
	Active, Finished                     []IdentityActivityRecord
	ActiveTruncated                      bool
	ActiveNextCursor, FinishedNextCursor string
	GeneratedAt                          time.Time
}

type IdentityActivityPageRequest struct {
	ActiveCursor, FinishedCursor      string
	Documents, Email, Batches, Titles []uuid.UUID
}

type IdentityActivityMembershipRecord struct {
	AccountID uuid.UUID
	Role      string
	Owner     bool
	Enabled   bool
	Claims    []string
}
