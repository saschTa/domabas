package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"mime"
	"mime/multipart"
	"net/http"
	"strconv"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/google/uuid"
)

func actor(ctx context.Context) (domain.DocumentActor, error) {
	principal, ok := transport.Principal(ctx)
	if !ok {
		return domain.DocumentActor{}, domain.ErrUnauthorized
	}
	return domain.DocumentActor{AccountID: principal.AccountID, UserID: principal.UserID, SessionDigest: principal.SessionDigest, CredentialRevision: principal.CredentialRevision}, nil
}

func (handler *DocumentHandler) failure(ctx context.Context, err error) models.DocumentErrorResponse {
	var validation domain.DocumentValidationError
	var maximum *http.MaxBytesError
	switch {
	case errors.Is(err, domain.ErrInvalidPDFPassword):
		return models.NewDocumentErrorResponse(400, "invalid_pdf_password", "the PDF password is incorrect")
	case errors.Is(err, domain.ErrUnauthorized):
		return models.NewDocumentErrorResponse(401, "unauthorized", "a valid session is required")
	case errors.Is(err, domain.ErrPasswordChangeRequired):
		return models.NewDocumentErrorResponse(403, "password_change_required", "change your password before continuing")
	case errors.Is(err, domain.ErrForbidden):
		return models.NewDocumentErrorResponse(403, "forbidden", "permission denied")
	case errors.Is(err, domain.ErrNotFound):
		return models.NewDocumentErrorResponse(404, "not_found", "document not found")
	case errors.Is(err, domain.ErrDuplicate):
		return models.NewDocumentErrorResponse(409, "duplicate_document", "these bytes already belong to a document in this namespace")
	case errors.Is(err, domain.ErrConflict), errors.Is(err, domain.ErrStaleJob):
		return models.NewDocumentErrorResponse(409, "conflict", "document state does not allow this operation")
	case errors.As(err, &validation):
		return models.NewDocumentErrorResponse(400, "invalid_request", validation.Error())
	case errors.Is(err, domain.ErrTooLarge), errors.As(err, &maximum), errors.Is(err, multipart.ErrMessageTooLarge):
		return models.NewDocumentErrorResponse(413, "body_too_large", "document request exceeds a limit")
	case errors.Is(err, domain.ErrUnsupportedMedia):
		return models.NewDocumentErrorResponse(415, "unsupported_media_type", "only PNG, JPEG, PDF and EML files are supported")
	case errors.Is(err, domain.ErrOverloaded):
		return models.NewDocumentErrorResponse(429, "overloaded", "document capacity is temporarily busy")
	case errors.Is(err, domain.ErrUnavailable), errors.Is(err, context.DeadlineExceeded), errors.Is(err, context.Canceled):
		return models.NewDocumentErrorResponse(503, "unavailable", "a document dependency is temporarily unavailable")
	default:
		handler.logger.ErrorContext(ctx, "document operation failed", "error", err)
		return models.NewDocumentErrorResponse(500, "internal_error", "an unexpected error occurred")
	}
}

func (handler *DocumentHandler) UploadDocument(ctx context.Context, request contract.UploadDocumentRequestObject) (contract.UploadDocumentResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if request.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "multipart body is required"), nil
	}
	var reservation domain.DocumentUploadReservation
	var metadata domain.DocumentMetadata
	seenFile, seenMetadata, accepted := false, false, false
	defer func() {
		if reservation.ID != "" && !accepted {
			cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := handler.ingestion.AbandonUpload(cleanup, a, reservation); err != nil {
				handler.logger.ErrorContext(cleanup, "defer unaccepted upload cleanup", "error", err)
			}
		}
	}()
	for count := 0; ; count++ {
		part, err := request.Body.NextRawPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			var maximum *http.MaxBytesError
			if errors.As(err, &maximum) || errors.Is(err, multipart.ErrMessageTooLarge) {
				return handler.failure(ctx, err), nil
			}
			return models.NewDocumentErrorResponse(400, "invalid_request", "multipart body is invalid"), nil
		}
		if count >= 2 {
			return models.NewDocumentErrorResponse(400, "invalid_request", "exactly one file and one metadata part are required"), nil
		}
		headerBytes := 0
		for key, values := range part.Header {
			if key != "Content-Disposition" && key != "Content-Type" {
				return models.NewDocumentErrorResponse(400, "invalid_request", "multipart part has an unsupported header"), nil
			}
			for _, value := range values {
				headerBytes += len(key) + len(value) + 4
			}
		}
		if headerBytes > 8192 {
			return handler.failure(ctx, domain.ErrTooLarge), nil
		}
		if len(part.Header.Values("Content-Disposition")) != 1 || len(part.Header.Values("Content-Type")) > 1 {
			return models.NewDocumentErrorResponse(400, "invalid_request", "multipart headers must be unique"), nil
		}
		switch part.FormName() {
		case "metadata":
			if seenMetadata || part.FileName() != "" {
				return models.NewDocumentErrorResponse(400, "invalid_request", "metadata must be one JSON string part"), nil
			}
			seenMetadata = true
			body, err := io.ReadAll(io.LimitReader(part, 32769))
			if err != nil {
				return handler.failure(ctx, err), nil
			}
			if len(body) > 32768 {
				return handler.failure(ctx, domain.ErrTooLarge), nil
			}
			metadata, err = models.DecodeMetadata(body)
			if err != nil {
				return models.NewDocumentErrorResponse(400, "invalid_request", err.Error()), nil
			}
		case "file":
			if seenFile || part.FileName() == "" {
				return models.NewDocumentErrorResponse(400, "invalid_request", "file must be one named binary part"), nil
			}
			seenFile = true
			reservation, err = handler.ingestion.ReserveUpload(ctx, a)
			if err != nil {
				return handler.failure(ctx, err), nil
			}
			if _, err = handler.ingestion.StageUpload(ctx, a, reservation, part.FileName(), part); err != nil {
				return handler.failure(ctx, err), nil
			}
		default:
			return models.NewDocumentErrorResponse(400, "invalid_request", "unknown multipart part"), nil
		}
		if err := part.Close(); err != nil {
			return handler.failure(ctx, err), nil
		}
	}
	if !seenFile || !seenMetadata {
		return models.NewDocumentErrorResponse(400, "invalid_request", "exactly one file and one metadata part are required"), nil
	}
	if remaining := models.RemainingUploadBody(ctx); remaining != nil {
		if _, err := io.Copy(io.Discard, remaining); err != nil {
			return handler.failure(ctx, err), nil
		}
	}
	document, err := handler.ingestion.AcceptUpload(ctx, a, reservation, metadata)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	accepted = true
	return contract.UploadDocument202JSONResponse(documentResponseMapper(document)), nil
}

func (handler *DocumentHandler) UpdateDocument(ctx context.Context, request contract.UpdateDocumentRequestObject) (contract.UpdateDocumentResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if request.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "metadata patch is required"), nil
	}
	body := request.Body
	var kind *string
	if body.Kind != nil {
		value := string(*body.Kind)
		kind = &value
	}
	patch := domain.DocumentMetadataPatch{Title: body.Title, Description: body.Description, Kind: kind, Sender: body.Sender, DocumentDate: body.DocumentDate, Subject: body.Subject, MessageID: body.MessageId, Tags: body.Tags, Recipients: body.Recipients, CC: body.Cc, BCC: body.Bcc}
	document, err := handler.ingestion.Update(ctx, a, request.Id.String(), patch)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.UpdateDocument200JSONResponse(documentResponseMapper(document)), nil
}
func (handler *DocumentHandler) DownloadDocument(ctx context.Context, request contract.DownloadDocumentRequestObject) (contract.DownloadDocumentResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	content, err := handler.ingestion.OpenContent(ctx, a, request.Id.String())
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return documentContentResponse{content: content}, nil
}
func (handler *DocumentHandler) GetDocumentProcessing(ctx context.Context, request contract.GetDocumentProcessingRequestObject) (contract.GetDocumentProcessingResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	processing, err := handler.ingestion.Processing(ctx, a, request.Id.String())
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.GetDocumentProcessing200JSONResponse(documentProcessingResponseMapper(processing)), nil
}
func (handler *DocumentHandler) RetryDocument(ctx context.Context, request contract.RetryDocumentRequestObject) (contract.RetryDocumentResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	processing, err := handler.ingestion.Retry(ctx, a, request.Id.String())
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.RetryDocument202JSONResponse(documentProcessingResponseMapper(processing)), nil
}
func (handler *DocumentHandler) SearchDocuments(ctx context.Context, request contract.SearchDocumentsRequestObject) (contract.SearchDocumentsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if request.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "search body is required"), nil
	}
	body := request.Body
	input := domain.DocumentSearchInput{Query: body.Query, Mode: string(body.Mode), Limit: 20}
	if body.Kinds != nil {
		for _, kind := range *body.Kinds {
			input.Kinds = append(input.Kinds, string(kind))
		}
	}
	if body.Limit != nil {
		input.Limit = *body.Limit
	}
	if body.Offset != nil {
		input.Offset = *body.Offset
	}
	if body.Tags != nil {
		input.Tags = *body.Tags
	}
	if body.Sender != nil {
		input.Sender = *body.Sender
	}
	if body.Recipient != nil {
		input.Recipient = *body.Recipient
	}
	if body.SenderMatch != nil {
		if !body.SenderMatch.Valid() {
			return models.NewDocumentErrorResponse(400, "invalid_request", "invalid sender matching mode"), nil
		}
		input.SenderMatch = string(*body.SenderMatch)
	}
	if body.RecipientMatch != nil {
		if !body.RecipientMatch.Valid() {
			return models.NewDocumentErrorResponse(400, "invalid_request", "invalid recipient matching mode"), nil
		}
		input.RecipientMatch = string(*body.RecipientMatch)
	}
	if body.Sort != nil {
		if *body.Sort == "" {
			return models.NewDocumentErrorResponse(400, "invalid_request", "invalid search sort"), nil
		}
		input.Sort = string(*body.Sort)
	}
	if body.Cursor != nil {
		if *body.Cursor == "" {
			return models.NewDocumentErrorResponse(400, "invalid_request", "cursor must not be empty"), nil
		}
		input.Cursor = *body.Cursor
	}
	if input.Limit < 1 {
		return models.NewDocumentErrorResponse(400, "invalid_request", "search limit must be positive"), nil
	}
	result, err := handler.ingestion.Search(ctx, a, input)
	if err != nil {
		response := handler.failure(ctx, err)
		handler.logger.WarnContext(ctx, "document search failed", "status", response.Status, "code", response.Body.Code)
		return response, nil
	}
	response := contract.DocumentSearchResults{Items: make([]contract.DocumentSearchItem, 0, len(result.Items)), Total: result.Total, NextCursor: documentOptionalStringMapper(result.NextCursor)}
	for _, item := range result.Items {
		if math.IsNaN(item.Score) || math.IsInf(item.Score, 0) {
			return handler.failure(ctx, domain.ErrUnavailable), nil
		}
		doc := item.Document
		summary := contract.DocumentSearchSummary{Thumbnail: documentThumbnailResponseMapper(doc.Thumbnail), Id: uuid.MustParse(doc.ID), Title: doc.Title, Kind: contract.DocumentSearchSummaryKind(doc.Kind), Tags: documentStringSliceMapper(doc.Tags), CreatedAt: doc.CreatedAt, DocumentDate: documentOptionalStringMapper(doc.DocumentDate)}
		if doc.Original != nil {
			summary.Original = &contract.DocumentSearchOriginal{Sha256: doc.Original.SHA256, MediaType: contract.DocumentSearchOriginalMediaType(doc.Original.MediaType), Size: doc.Original.Size}
		}
		if doc.ProcessingState != "" {
			state := contract.DocumentSearchSummaryProcessingState(doc.ProcessingState)
			summary.ProcessingState = &state
		}
		response.Items = append(response.Items, contract.DocumentSearchItem{Document: summary, Score: item.Score, Snippet: item.Snippet})
	}
	encoded, err := json.Marshal(response)
	if err != nil || len(encoded) > 512<<10 {
		return handler.failure(ctx, domain.ErrUnavailable), nil
	}
	return contract.SearchDocuments200JSONResponse(response), nil
}
func (handler *DocumentHandler) GetDocumentProcessingConfiguration(ctx context.Context, _ contract.GetDocumentProcessingConfigurationRequestObject) (contract.GetDocumentProcessingConfigurationResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	configuration, err := handler.ingestion.GetProcessingConfiguration(ctx, a)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.GetDocumentProcessingConfiguration200JSONResponse(documentConfigurationResponseMapper(configuration)), nil
}

func (handler *DocumentHandler) GetDocumentModelContext(ctx context.Context, request contract.GetDocumentModelContextRequestObject) (contract.GetDocumentModelContextResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	value, err := handler.ingestion.ModelContext(ctx, a, request.Params.Model)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.GetDocumentModelContext200JSONResponse{Model: value.Model, MaxContextLength: value.MaxContextLength}, nil
}
func (handler *DocumentHandler) UpdateDocumentProcessingConfiguration(ctx context.Context, request contract.UpdateDocumentProcessingConfigurationRequestObject) (contract.UpdateDocumentProcessingConfigurationResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	if request.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "configuration is required"), nil
	}
	input := domain.DocumentProcessingConfiguration{ExpectedRevision: request.Body.ExpectedRevision, Language: string(request.Body.Language), Segmentation: string(request.Body.Segmentation)}
	if v := request.Body.Llm; v != nil {
		input.LLMUpdate = &domain.DocumentLLMConfigurationUpdate{PropertyThinkingEnabled: v.PropertyThinkingEnabled, InvoiceThinkingEnabled: v.InvoiceThinkingEnabled, LMStudioCompatibility: v.LmStudioCompatibility, Enabled: v.Enabled, InvoiceEnabled: v.InvoiceEnabled, ContextLength: v.ContextLength, Provider: string(v.Provider), Model: v.Model, BaseURL: v.BaseUrl, APIKey: v.ApiKey, ClearAPIKey: v.ClearApiKey != nil && *v.ClearApiKey}
	}
	configuration, err := handler.ingestion.SetProcessingConfiguration(ctx, a, input)
	if err != nil {
		return handler.failure(ctx, err), nil
	}
	return contract.UpdateDocumentProcessingConfiguration200JSONResponse(documentConfigurationResponseMapper(configuration)), nil
}

func (response documentContentResponse) VisitDownloadDocumentResponse(w http.ResponseWriter) error {
	defer response.content.Reader.Close()
	w.Header().Set("Content-Type", response.content.File.MediaType)
	w.Header().Set("Content-Length", strconv.FormatInt(response.content.File.Size, 10))
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": response.content.File.OriginalFilename}))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(200)
	_, err := io.CopyN(w, response.content.Reader, response.content.File.Size)
	return err
}
