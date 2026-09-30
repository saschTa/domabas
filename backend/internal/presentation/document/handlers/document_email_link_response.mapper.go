package handlers

import (
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func documentEmailLinkResponseMapper(item m.DocumentEmailLink) contract.DocumentLink {
	return contract.DocumentLink{DocumentId: uuid.MustParse(item.DocumentID), Title: item.Title, MediaType: contract.DocumentLinkMediaType(item.MediaType)}
}
