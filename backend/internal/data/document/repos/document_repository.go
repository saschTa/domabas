package repos

import (
	"context"
	"errors"
	"fmt"

	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	documentinterfaces "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type DocumentRepository struct{ source DocumentSource }

var _ documentinterfaces.DocumentRepository = (*DocumentRepository)(nil)

func NewDocumentRepository(source DocumentSource) *DocumentRepository {
	return &DocumentRepository{source: source}
}

func (repository *DocumentRepository) Create(ctx context.Context, accountID string, doc documentmodels.Document) (documentmodels.Document, error) {
	if err := documentmodels.ValidateAccountID(accountID); err != nil {
		return documentmodels.Document{}, err
	}
	account, err := uuid.Parse(accountID)
	if err != nil {
		return documentmodels.Document{}, fmt.Errorf("parse account ID: %w", err)
	}
	id, err := uuid.Parse(doc.ID)
	if err != nil {
		return documentmodels.Document{}, fmt.Errorf("parse document ID: %w", err)
	}
	record, err := repository.source.CreateDocument(ctx, model.Documents{ID: id, AccountID: &account, Title: doc.Title, Description: doc.Description, CreatedAt: doc.CreatedAt})
	if err != nil {
		return documentmodels.Document{}, err
	}
	return documentRecordToDomainMapper(record), nil
}

func (repository *DocumentRepository) Get(ctx context.Context, accountID, id string) (documentmodels.Document, error) {
	if err := documentmodels.ValidateAccountID(accountID); err != nil {
		return documentmodels.Document{}, err
	}
	record, err := repository.source.GetDocument(ctx, accountID, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return documentmodels.Document{}, documentmodels.ErrNotFound
	}
	if err != nil {
		return documentmodels.Document{}, err
	}
	return documentRecordToDomainMapper(record), nil
}

func (repository *DocumentRepository) List(ctx context.Context, accountID string, page documentmodels.DocumentPageRequest) (documentmodels.DocumentPage, error) {
	if err := documentmodels.ValidateAccountID(accountID); err != nil {
		return documentmodels.DocumentPage{}, err
	}
	records, err := repository.source.ListDocuments(ctx, accountID, page.Limit, page.Offset, page.Cursor)
	if err != nil {
		return documentmodels.DocumentPage{}, err
	}
	result := documentmodels.DocumentPage{Items: make([]documentmodels.Document, 0, len(records.Items)), Total: records.Total, NextCursor: records.NextCursor}
	for _, record := range records.Items {
		result.Items = append(result.Items, documentRecordToDomainMapper(record))
	}
	return result, nil
}
