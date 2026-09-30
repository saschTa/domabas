package handlers

import (
	"context"
	"errors"
	"log/slog"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type DocumentHandler struct {
	thumbnails DocumentThumbnailService
	documents  DocumentService
	ingestion  DocumentIngestionService
	imports    DocumentImportService
	vocabulary DocumentVocabularyService
	logger     *slog.Logger
}

func NewDocumentHandler(documents DocumentService, ingestion DocumentIngestionService, imports DocumentImportService, vocabulary DocumentVocabularyService, logger *slog.Logger) *DocumentHandler {
	return &DocumentHandler{documents: documents, ingestion: ingestion, imports: imports, vocabulary: vocabulary, logger: logger}
}

func (handler *DocumentHandler) CreateDocument(ctx context.Context, request contract.CreateDocumentRequestObject) (contract.CreateDocumentResponseObject, error) {
	principal, authenticated := transport.Principal(ctx)
	if !authenticated {
		return contract.CreateDocument401JSONResponse{UnauthorizedJSONResponse: contract.UnauthorizedJSONResponse{Code: "unauthorized", Message: "authentication is required"}}, nil
	}
	var model models.DocumentCreateRequest
	if request.Body != nil {
		model = models.DocumentCreateRequest{Title: &request.Body.Title, Description: request.Body.Description}
	}
	input, err := model.DomainInput()
	if err != nil {
		return contract.CreateDocument400JSONResponse{BadRequestJSONResponse: contract.BadRequestJSONResponse{Code: "invalid_request", Message: err.Error()}}, nil
	}
	doc, err := handler.documents.Create(ctx, principal.AccountID, input)
	var validation domain.DocumentValidationError
	if errors.As(err, &validation) {
		return contract.CreateDocument400JSONResponse{BadRequestJSONResponse: contract.BadRequestJSONResponse{Code: "invalid_request", Message: validation.Error()}}, nil
	}
	if err != nil {
		handler.logger.ErrorContext(ctx, "create document failed", "error", err)
		return contract.CreateDocument500JSONResponse{InternalErrorJSONResponse: internalError()}, nil
	}
	return contract.CreateDocument201JSONResponse(documentResponseMapper(doc)), nil
}

func (handler *DocumentHandler) GetDocument(ctx context.Context, request contract.GetDocumentRequestObject) (contract.GetDocumentResponseObject, error) {
	principal, authenticated := transport.Principal(ctx)
	if !authenticated {
		return contract.GetDocument401JSONResponse{UnauthorizedJSONResponse: contract.UnauthorizedJSONResponse{Code: "unauthorized", Message: "authentication is required"}}, nil
	}
	doc, err := handler.documents.Get(ctx, principal.AccountID, request.Id.String())
	if errors.Is(err, domain.ErrNotFound) {
		return contract.GetDocument404JSONResponse{NotFoundJSONResponse: contract.NotFoundJSONResponse{Code: "not_found", Message: "document not found"}}, nil
	}
	if err != nil {
		handler.logger.ErrorContext(ctx, "get document failed", "error", err)
		return contract.GetDocument500JSONResponse{InternalErrorJSONResponse: internalError()}, nil
	}
	return contract.GetDocument200JSONResponse(documentResponseMapper(doc)), nil
}

func (handler *DocumentHandler) ListDocuments(ctx context.Context, request contract.ListDocumentsRequestObject) (contract.ListDocumentsResponseObject, error) {
	principal, authenticated := transport.Principal(ctx)
	if !authenticated {
		return contract.ListDocuments401JSONResponse{UnauthorizedJSONResponse: contract.UnauthorizedJSONResponse{Code: "unauthorized", Message: "authentication is required"}}, nil
	}
	model := models.DocumentListRequest{Limit: request.Params.Limit, Offset: request.Params.Offset, Cursor: request.Params.Cursor}
	page, err := model.DomainPage()
	if err != nil {
		return contract.ListDocuments400JSONResponse{BadRequestJSONResponse: contract.BadRequestJSONResponse{Code: "invalid_request", Message: err.Error()}}, nil
	}
	result, err := handler.documents.List(ctx, principal.AccountID, page)
	var validation domain.DocumentValidationError
	if errors.As(err, &validation) {
		return contract.ListDocuments400JSONResponse{BadRequestJSONResponse: contract.BadRequestJSONResponse{Code: "invalid_request", Message: validation.Error()}}, nil
	}
	if err != nil {
		handler.logger.ErrorContext(ctx, "list documents failed", "error", err)
		return contract.ListDocuments500JSONResponse{InternalErrorJSONResponse: internalError()}, nil
	}
	items := make([]contract.Document, 0, len(result.Items))
	for _, doc := range result.Items {
		items = append(items, documentResponseMapper(doc))
	}
	return contract.ListDocuments200JSONResponse{Items: items, Total: result.Total, NextCursor: documentOptionalStringMapper(result.NextCursor)}, nil
}

func internalError() contract.InternalErrorJSONResponse {
	return contract.InternalErrorJSONResponse{Code: "internal_error", Message: "an unexpected error occurred"}
}

type DocumentThumbnailService interface {
	Read(context.Context, domain.DocumentActor, string, string) (domain.DocumentThumbnailContent, error)
}

func (h *DocumentHandler) WithThumbnails(s DocumentThumbnailService) *DocumentHandler {
	h.thumbnails = s
	return h
}
