package handlers

import (
	"context"
	"errors"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	r "github.com/domabas/domabas/backend/internal/presentation/paperless/models"
	"github.com/google/uuid"
)

type PaperlessService interface {
	Settings(context.Context, d.DocumentActor) (m.PaperlessSettings, error)
	UpdateSettings(context.Context, d.DocumentActor, m.PaperlessSettingsUpdate) (m.PaperlessSettings, error)
	Create(context.Context, d.DocumentActor, string, m.PaperlessConnection) (m.PaperlessRun, error)
	List(context.Context, d.DocumentActor, m.PaperlessPageRequest) (m.PaperlessRunPage, error)
	Outcomes(context.Context, d.DocumentActor, string, m.PaperlessPageRequest) (m.PaperlessOutcomePage, error)
	Get(context.Context, d.DocumentActor, string) (m.PaperlessRun, error)
	Cancel(context.Context, d.DocumentActor, string) (m.PaperlessRun, error)
}
type PaperlessHandler struct{ service PaperlessService }

func NewPaperlessHandler(service PaperlessService) *PaperlessHandler {
	return &PaperlessHandler{service: service}
}
func failure(err error) r.PaperlessErrorResponse {
	var source m.PaperlessFailure
	switch {
	case errors.As(err, &source):
		if source.Code == "invalid_settings" {
			return r.PaperlessErrorResponse{Status: 400, Code: source.Code, Message: "Provide a concurrency from 1 to 10 and the current settings revision."}
		}
		if source.Code == "invalid_pagination" {
			return r.PaperlessErrorResponse{Status: 400, Code: source.Code, Message: "Invalid pagination parameters or cursor."}
		}
		return r.PaperlessErrorResponse{Status: 422, Code: source.Code, Message: "Paperless import configuration is unavailable or invalid."}
	case errors.Is(err, d.ErrUnauthorized):
		return r.PaperlessErrorResponse{Status: 401, Code: "unauthorized", Message: "Sign in again."}
	case errors.Is(err, d.ErrForbidden):
		return r.PaperlessErrorResponse{Status: 403, Code: "forbidden", Message: "Import permission is unavailable."}
	case errors.Is(err, d.ErrNotFound):
		return r.PaperlessErrorResponse{Status: 404, Code: "not_found", Message: "Import not found."}
	case errors.Is(err, d.ErrConflict):
		return r.PaperlessErrorResponse{Status: 409, Code: "conflict", Message: "An import is already active or this request ID was used with different connection details."}
	case errors.Is(err, m.ErrBusy):
		return r.PaperlessErrorResponse{Status: 429, Code: "overloaded", Message: "The import queue is full."}
	}
	return r.PaperlessErrorResponse{Status: 503, Code: "unavailable", Message: "Import state could not be confirmed. Retry using the same request ID."}
}

func (h *PaperlessHandler) GetPaperlessSettings(ctx context.Context, _ contract.GetPaperlessSettingsRequestObject) (contract.GetPaperlessSettingsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return failure(d.ErrUnavailable), nil
	}
	settings, err := h.service.Settings(ctx, a)
	if err != nil {
		return failure(err), nil
	}
	return contract.GetPaperlessSettings200JSONResponse(paperlessSettingsResponseMapper(settings)), nil
}

func (h *PaperlessHandler) UpdatePaperlessSettings(ctx context.Context, request contract.UpdatePaperlessSettingsRequestObject) (contract.UpdatePaperlessSettingsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return failure(d.ErrUnavailable), nil
	}
	if request.Body == nil {
		return failure(m.PaperlessFailure{Code: "invalid_settings"}), nil
	}
	settings, err := h.service.UpdateSettings(ctx, a, m.PaperlessSettingsUpdate{RetrievalConcurrency: request.Body.RetrievalConcurrency, ExpectedRevision: request.Body.ExpectedRevision})
	if errors.Is(err, d.ErrConflict) {
		return r.PaperlessErrorResponse{Status: 409, Code: "conflict", Message: "Paperless settings changed. Reload and save again."}, nil
	}
	if err != nil {
		return failure(err), nil
	}
	return contract.UpdatePaperlessSettings200JSONResponse(paperlessSettingsResponseMapper(settings)), nil
}
func actor(ctx context.Context) (d.DocumentActor, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return d.DocumentActor{}, d.ErrUnauthorized
	}
	return d.DocumentActor{AccountID: p.AccountID, UserID: p.UserID, SessionDigest: p.SessionDigest, CredentialRevision: p.CredentialRevision}, nil
}

func (h *PaperlessHandler) GetPaperlessOptions(context.Context, contract.GetPaperlessOptionsRequestObject) (contract.GetPaperlessOptionsResponseObject, error) {
	return contract.GetPaperlessOptions200JSONResponse{PageSize: m.PageSize}, nil
}
func (h *PaperlessHandler) StartPaperlessRun(ctx context.Context, request contract.StartPaperlessRunRequestObject) (contract.StartPaperlessRunResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return failure(m.PaperlessFailure{Code: "not_configured"}), nil
	}
	b := request.Body
	if b == nil || b.Token == nil || b.RequestId == uuid.Nil {
		return failure(m.PaperlessFailure{Code: "invalid_request"}), nil
	}
	v, err := h.service.Create(ctx, a, b.RequestId.String(), m.PaperlessConnection{ServerURL: b.ServerUrl, Token: *b.Token})
	if err != nil {
		return failure(err), nil
	}
	return contract.StartPaperlessRun202JSONResponse(paperlessRunResponseMapper(v)), nil
}
func (h *PaperlessHandler) ListPaperlessRuns(ctx context.Context, request contract.ListPaperlessRunsRequestObject) (contract.ListPaperlessRunsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return contract.ListPaperlessRuns200JSONResponse{Counts: &contract.JobStatusCounts{Groups: []contract.JobStatusCount{}}, Items: []contract.PaperlessRun{}}, nil
	}
	page := paperlessPageRequestMapper(request.Params.Limit, request.Params.Cursor)
	page.ActiveOnly = request.Params.ActiveOnly != nil && *request.Params.ActiveOnly
	if request.Params.Status != nil {
		page.Status = string(*request.Params.Status)
	}
	values, err := h.service.List(ctx, a, page)
	if err != nil {
		return failure(err), nil
	}
	items := []contract.PaperlessRun{}
	for _, v := range values.Items {
		items = append(items, paperlessRunResponseMapper(v))
	}
	return contract.ListPaperlessRuns200JSONResponse{Counts: paperlessJobCountsResponseMapper(values.Counts), Items: items, NextCursor: paperlessOptionalStringMapper(values.NextCursor)}, nil
}
func (h *PaperlessHandler) GetPaperlessRun(ctx context.Context, request contract.GetPaperlessRunRequestObject) (contract.GetPaperlessRunResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return failure(d.ErrNotFound), nil
	}
	v, err := h.service.Get(ctx, a, request.RunId.String())
	if err != nil {
		return failure(err), nil
	}
	return contract.GetPaperlessRun200JSONResponse(paperlessRunResponseMapper(v)), nil
}
func (h *PaperlessHandler) CancelPaperlessRun(ctx context.Context, request contract.CancelPaperlessRunRequestObject) (contract.CancelPaperlessRunResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return failure(d.ErrNotFound), nil
	}
	v, err := h.service.Cancel(ctx, a, request.RunId.String())
	if err != nil {
		return failure(err), nil
	}
	return contract.CancelPaperlessRun200JSONResponse(paperlessRunResponseMapper(v)), nil
}

func (h *PaperlessHandler) ListPaperlessOutcomes(ctx context.Context, request contract.ListPaperlessOutcomesRequestObject) (contract.ListPaperlessOutcomesResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return failure(err), nil
	}
	if h == nil || h.service == nil {
		return failure(d.ErrNotFound), nil
	}
	page := paperlessPageRequestMapper(request.Params.Limit, request.Params.Cursor)
	if request.Params.Status != nil {
		page.Status = string(*request.Params.Status)
	}
	values, err := h.service.Outcomes(ctx, a, request.RunId.String(), page)
	if err != nil {
		return failure(err), nil
	}
	return contract.ListPaperlessOutcomes200JSONResponse{Items: paperlessOutcomesResponseMapper(values.Items), NextCursor: paperlessOptionalStringMapper(values.NextCursor)}, nil
}
