package interfaces

import (
	"context"

	"github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentVocabularyRepository interface {
	List(context.Context, models.DocumentActor, models.DocumentVocabularyInput) (models.DocumentVocabularyPage, error)
}
