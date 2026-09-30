package handlers

import (
	"context"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

type DocumentVocabularyService interface {
	List(context.Context, domain.DocumentActor, domain.DocumentVocabularyInput) (domain.DocumentVocabularyPage, error)
}

func (handler *DocumentHandler) ListDocumentVocabulary(ctx context.Context, request contract.ListDocumentVocabularyRequestObject) (contract.ListDocumentVocabularyResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	input := domain.DocumentVocabularyInput{Field: string(request.Params.Field), Limit: 40}
	if request.Params.Query != nil {
		input.Query = *request.Params.Query
	}
	if request.Params.Limit != nil {
		input.Limit = *request.Params.Limit
	}
	if request.Params.Cursor != nil {
		input.Cursor = *request.Params.Cursor
		if input.Cursor == "" {
			return models.NewDocumentErrorResponse(400, "invalid_request", "cursor must not be empty"), nil
		}
	}
	if input.Limit < 1 {
		return models.NewDocumentErrorResponse(400, "invalid_request", "vocabulary limit must be positive"), nil
	}
	page, err := handler.vocabulary.List(ctx, a, input)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	response := contract.DocumentVocabularyPage{Items: make([]contract.DocumentVocabularyOption, 0, len(page.Items)), NextCursor: documentOptionalStringMapper(page.NextCursor)}
	for _, option := range page.Items {
		response.Items = append(response.Items, contract.DocumentVocabularyOption{Key: option.Key, Value: option.Value})
	}
	return contract.ListDocumentVocabulary200JSONResponse(response), nil
}
