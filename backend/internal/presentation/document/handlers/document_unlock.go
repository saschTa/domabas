package handlers

import (
	"context"

	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func (handler *DocumentHandler) UnlockDocument(ctx context.Context, request contract.UnlockDocumentRequestObject) (contract.UnlockDocumentResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if request.Body == nil || request.Body.Password == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "password and generation are required"), nil
	}
	result, err := handler.ingestion.Unlock(ctx, a, request.Id.String(), request.Body.Generation, *request.Body.Password)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.UnlockDocument202JSONResponse(documentProcessingResponseMapper(result)), nil
}
