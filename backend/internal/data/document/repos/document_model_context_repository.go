package repos

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentModelContextSource interface {
	ModelContext(context.Context, string) (int, error)
}

type DocumentModelContextRepository struct {
	source DocumentModelContextSource
}

func NewDocumentModelContextRepository(source DocumentModelContextSource) *DocumentModelContextRepository {
	return &DocumentModelContextRepository{source: source}
}

func (r *DocumentModelContextRepository) ModelContext(ctx context.Context, model string) (m.DocumentModelContext, error) {
	maximum, err := r.source.ModelContext(ctx, model)
	if err != nil {
		return m.DocumentModelContext{}, errors.Join(m.ErrUnavailable, err)
	}
	return m.DocumentModelContext{Model: model, MaxContextLength: maximum}, err
}
