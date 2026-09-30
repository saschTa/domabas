package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/identity/models"
	m "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/google/uuid"
)

func identityActivityIDMapper(value *uuid.UUID) *string {
	if value == nil {
		return nil
	}
	id := value.String()
	return &id
}

func identityActivityItemsMapper(records []r.IdentityActivityRecord) []m.PersonalActivityItem {
	items := make([]m.PersonalActivityItem, 0, len(records))
	for _, record := range records {
		items = append(items, m.PersonalActivityItem{ID: record.ID.String(), Kind: record.Kind, NamespaceID: record.NamespaceID.String(), NamespaceName: record.NamespaceName, Status: record.Status, Stage: record.Stage, DocumentID: identityActivityIDMapper(record.DocumentID), ProviderID: identityActivityIDMapper(record.ProviderID), BatchID: identityActivityIDMapper(record.BatchID), Title: record.Title, FailureCode: record.FailureCode, CreatedAt: record.CreatedAt.UTC(), StartedAt: record.StartedAt, FinishedAt: record.FinishedAt, CanOpen: record.CanOpen})
	}
	return items
}
