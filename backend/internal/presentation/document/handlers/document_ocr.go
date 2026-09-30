package handlers

import (
	"context"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func (handler *DocumentHandler) GetDocumentOCR(ctx context.Context, request contract.GetDocumentOCRRequestObject) (contract.GetDocumentOCRResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	result, err := handler.ingestion.OCR(ctx, a, request.Id.String())
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.GetDocumentOCR200JSONResponse(documentOCRResponseMapper(result)), nil
}
func (handler *DocumentHandler) UpdateDocumentOCR(ctx context.Context, request contract.UpdateDocumentOCRRequestObject) (contract.UpdateDocumentOCRResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if request.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "OCR correction is required"), nil
	}
	result, err := handler.ingestion.CorrectOCR(ctx, a, request.Id.String(), domain.DocumentOCRCorrection{Revision: request.Body.Revision, Text: request.Body.Text})
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.UpdateDocumentOCR200JSONResponse(documentOCRResponseMapper(result)), nil
}
func (handler *DocumentHandler) DeleteDocument(ctx context.Context, request contract.DeleteDocumentRequestObject) (contract.DeleteDocumentResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if err := handler.ingestion.Delete(ctx, a, request.Id.String()); err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.DeleteDocument204Response{}, nil
}
