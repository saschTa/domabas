package services

import (
	"context"

	"github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	"github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type DocumentVocabularyService struct {
	repository interfaces.DocumentVocabularyRepository
	authority  interfaces.DocumentAuthority
}

func NewDocumentVocabularyService(repository interfaces.DocumentVocabularyRepository, authority interfaces.DocumentAuthority) *DocumentVocabularyService {
	return &DocumentVocabularyService{repository: repository, authority: authority}
}

func (service *DocumentVocabularyService) List(ctx context.Context, actor models.DocumentActor, input models.DocumentVocabularyInput) (models.DocumentVocabularyPage, error) {
	if _, err := resolveDocumentAuthority(ctx, service.authority, actor, identity.DocumentsRead, identity.DocumentsSearch); err != nil {
		return models.DocumentVocabularyPage{}, err
	}
	input, err := input.Normalize()
	if err != nil {
		return models.DocumentVocabularyPage{}, err
	}
	return service.repository.List(ctx, actor, input)
}
