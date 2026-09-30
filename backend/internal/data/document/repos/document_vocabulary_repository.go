package repos

import (
	"context"
	"crypto/sha256"
	"encoding/hex"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentVocabularySource interface {
	ListVocabularyRecords(context.Context, m.DocumentActor, m.DocumentVocabularyInput) (r.DocumentVocabularyRecords, error)
}

type DocumentVocabularyRepository struct {
	source DocumentVocabularySource
}

var _ p.DocumentVocabularyRepository = (*DocumentVocabularyRepository)(nil)

func NewDocumentVocabularyRepository(source DocumentVocabularySource) *DocumentVocabularyRepository {
	return &DocumentVocabularyRepository{source: source}
}

func (repository *DocumentVocabularyRepository) List(ctx context.Context, actor m.DocumentActor, input m.DocumentVocabularyInput) (m.DocumentVocabularyPage, error) {
	records, err := repository.source.ListVocabularyRecords(ctx, actor, input)
	if err != nil {
		return m.DocumentVocabularyPage{}, err
	}
	page := m.DocumentVocabularyPage{Items: make([]m.DocumentVocabularyOption, 0, len(records.Items)), NextCursor: records.NextCursor}
	for _, record := range records.Items {
		digest := sha256.Sum256([]byte(input.Field + "\x00" + record.ComparisonKey))
		page.Items = append(page.Items, m.DocumentVocabularyOption{Key: hex.EncodeToString(digest[:]), Value: record.Value})
	}
	return page, nil
}
