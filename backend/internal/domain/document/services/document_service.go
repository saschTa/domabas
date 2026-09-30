package services

import (
	"context"
	"crypto/rand"
	"fmt"
	"strings"
	"time"

	documentinterfaces "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentService struct {
	repository documentinterfaces.DocumentRepository
	now        func() time.Time
}

func NewDocumentService(repository documentinterfaces.DocumentRepository, now func() time.Time) *DocumentService {
	return &DocumentService{repository: repository, now: now}
}

func (service *DocumentService) Create(ctx context.Context, accountID string, input documentmodels.DocumentCreateInput) (documentmodels.Document, error) {
	if err := documentmodels.ValidateAccountID(accountID); err != nil {
		return documentmodels.Document{}, err
	}
	if err := input.Validate(); err != nil {
		return documentmodels.Document{}, err
	}
	id := make([]byte, 16)
	if _, err := rand.Read(id); err != nil {
		return documentmodels.Document{}, fmt.Errorf("generate document ID: %w", err)
	}
	id[6] = (id[6] & 0x0f) | 0x40
	id[8] = (id[8] & 0x3f) | 0x80
	document := documentmodels.Document{
		ID:    fmt.Sprintf("%x-%x-%x-%x-%x", id[0:4], id[4:6], id[6:8], id[8:10], id[10:16]),
		Title: strings.TrimSpace(input.Title), Description: input.Description, CreatedAt: service.now().UTC(),
	}
	return service.repository.Create(ctx, accountID, document)
}

func (service *DocumentService) Get(ctx context.Context, accountID, id string) (documentmodels.Document, error) {
	if err := documentmodels.ValidateAccountID(accountID); err != nil {
		return documentmodels.Document{}, err
	}
	return service.repository.Get(ctx, accountID, id)
}

func (service *DocumentService) List(ctx context.Context, accountID string, page documentmodels.DocumentPageRequest) (documentmodels.DocumentPage, error) {
	if err := documentmodels.ValidateAccountID(accountID); err != nil {
		return documentmodels.DocumentPage{}, err
	}
	if err := page.Validate(); err != nil {
		return documentmodels.DocumentPage{}, err
	}
	return service.repository.List(ctx, accountID, page)
}
