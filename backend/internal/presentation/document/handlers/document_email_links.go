package handlers

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

type DocumentImportService interface {
	EmailLinks(context.Context, m.DocumentActor, string, int, string) (m.DocumentEmailLinks, error)
	EmailParents(context.Context, m.DocumentActor, string, int, string) (m.DocumentEmailParents, error)
}

func (handler *DocumentHandler) GetDocumentEmailLinks(ctx context.Context, req contract.GetDocumentEmailLinksRequestObject) (contract.GetDocumentEmailLinksResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	input, err := pageInput(req.Params.Limit, req.Params.Cursor)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	value, err := handler.imports.EmailLinks(ctx, a, req.Id.String(), input.Limit, input.Cursor)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	response := contract.DocumentEmailLinks{Attachments: []contract.DocumentEmailAttachment{}, NextCursor: documentOptionalStringMapper(value.NextCursor)}
	for _, item := range value.Attachments {
		var document *contract.DocumentLink
		if item.Document != nil {
			link := documentEmailLinkResponseMapper(*item.Document)
			document = &link
		}
		response.Attachments = append(response.Attachments, contract.DocumentEmailAttachment{Part: item.Part, Filename: item.Filename, Status: contract.DocumentEmailAttachmentStatus(item.Status), FailureCode: documentOptionalStringMapper(item.FailureCode), Document: document})
	}
	return contract.GetDocumentEmailLinks200JSONResponse(response), nil
}
func (handler *DocumentHandler) GetDocumentEmailParents(ctx context.Context, req contract.GetDocumentEmailParentsRequestObject) (contract.GetDocumentEmailParentsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	input, err := pageInput(req.Params.Limit, req.Params.Cursor)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	value, err := handler.imports.EmailParents(ctx, a, req.Id.String(), input.Limit, input.Cursor)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	response := contract.DocumentEmailParents{Items: []contract.DocumentLink{}, NextCursor: documentOptionalStringMapper(value.NextCursor)}
	for _, item := range value.Items {
		response.Items = append(response.Items, documentEmailLinkResponseMapper(item))
	}
	return contract.GetDocumentEmailParents200JSONResponse(response), nil
}
