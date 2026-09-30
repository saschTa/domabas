package handlers

import (
	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func identityActivityUUIDMapper(value *string) *uuid.UUID {
	if value == nil {
		return nil
	}
	id := uuid.MustParse(*value)
	return &id
}

func identityActivityResponseMapper(items []domain.PersonalActivityItem) []contract.PersonalActivityItem {
	result := make([]contract.PersonalActivityItem, 0, len(items))
	for _, item := range items {
		result = append(result, contract.PersonalActivityItem{Id: uuid.MustParse(item.ID), Kind: contract.PersonalActivityItemKind(item.Kind), NamespaceId: uuid.MustParse(item.NamespaceID), NamespaceName: item.NamespaceName, Status: contract.PersonalActivityItemStatus(item.Status), Stage: item.Stage, CreatedAt: item.CreatedAt, StartedAt: item.StartedAt, FinishedAt: item.FinishedAt, DocumentId: identityActivityUUIDMapper(item.DocumentID), ProviderId: identityActivityUUIDMapper(item.ProviderID), BatchId: identityActivityUUIDMapper(item.BatchID), Title: item.Title, FailureCode: item.FailureCode, CanOpen: item.CanOpen})
	}
	return result
}

func identityActivityCursorMapper(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}
