package handlers

import (
	"context"
	"errors"
	"log/slog"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	responses "github.com/domabas/domabas/backend/internal/presentation/email/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/google/uuid"
)

type EmailService interface {
	Available() bool
	List(context.Context, m.EmailActor, int, string) (m.EmailProviderPage, error)
	Get(context.Context, m.EmailActor, string) (m.EmailProvider, error)
	Create(context.Context, m.EmailActor, m.EmailProviderInput) (m.EmailProvider, error)
	Update(context.Context, m.EmailActor, m.EmailProviderInput) (m.EmailProvider, error)
	Delete(context.Context, m.EmailActor, string, int64) error
	Test(context.Context, m.EmailActor, m.EmailTestConnection) (m.EmailTestResult, error)
	Runs(context.Context, m.EmailActor, m.EmailRunQuery) (m.EmailRunPage, error)
	Run(context.Context, m.EmailActor, string) (m.EmailRun, error)
	Start(context.Context, m.EmailActor, string, m.EmailStartRun) (m.EmailRun, error)
}
type EmailHandler struct {
	service EmailService
	logger  *slog.Logger
}

func NewEmailHandler(service EmailService, logger *slog.Logger) *EmailHandler {
	return &EmailHandler{service: service, logger: logger}
}
func actor(ctx context.Context) (m.EmailActor, error) {
	principal, ok := transport.Principal(ctx)
	if !ok {
		return m.EmailActor{}, m.ErrForbidden
	}
	return m.EmailActor{AccountID: principal.AccountID, UserID: principal.UserID, SessionDigest: principal.SessionDigest, CredentialRevision: principal.CredentialRevision}, nil
}
func (h *EmailHandler) failure(ctx context.Context, err error) responses.EmailErrorResponse {
	status, code, message := 500, "internal_error", "an unexpected error occurred"
	var validation m.EmailValidationError
	switch {
	case errors.As(err, &validation):
		status, code, message = 400, "invalid_request", validation.Message
	case errors.Is(err, m.ErrNotFound):
		status, code, message = 404, "not_found", "email resource unavailable"
	case errors.Is(err, m.ErrForbidden):
		status, code, message = 403, "forbidden", "permission denied"
	case errors.Is(err, m.ErrConflict):
		status, code, message = 409, "conflict", "email resource changed; reload and review"
	case errors.Is(err, m.ErrRateLimited):
		status, code, message = 429, "rate_limited", "connection test temporarily busy"
	case errors.Is(err, m.ErrUnavailable):
		status, code, message = 503, "unavailable", "email ingestion temporarily unavailable"
	default:
		h.logger.ErrorContext(ctx, "email operation failed")
	}
	return responses.NewEmailErrorResponse(status, code, message)
}

func page(limit *int, cursor *string) (int, string, error) {
	n, value := 20, ""
	if limit != nil {
		n = int(*limit)
	}
	if cursor != nil {
		value = *cursor
		if value == "" {
			return n, value, m.EmailValidationError{Message: "cursor must not be empty"}
		}
	}
	if n < 1 || n > 50 {
		return n, value, m.EmailValidationError{Message: "limit must be 1 to 50"}
	}
	return n, value, nil
}
func (h *EmailHandler) GetEmailCapabilities(ctx context.Context, _ contract.GetEmailCapabilitiesRequestObject) (contract.GetEmailCapabilitiesResponseObject, error) {
	var reason *contract.EmailCapabilitiesUnavailableReason
	if !h.service.Available() {
		v := contract.EmailCapabilitiesUnavailableReason("not_configured")
		reason = &v
	}
	return contract.GetEmailCapabilities200JSONResponse{CredentialsAvailable: h.service.Available(), UnavailableReason: reason, Transport: "implicit_tls", DefaultIntervalMinutes: 15, MinIntervalMinutes: 5, MaxIntervalMinutes: 1440, DefaultMaxAgeDays: 30, MinMaxAgeDays: 1, MaxMaxAgeDays: 3650, DefaultPageSize: 50, MinPageSize: 1, MaxPageSize: 100, MaxProviders: 20}, nil
}
func (h *EmailHandler) ListEmailProviders(ctx context.Context, request contract.ListEmailProvidersRequestObject) (contract.ListEmailProvidersResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	limit, cursor, err := page(request.Params.Limit, request.Params.Cursor)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	result, err := h.service.List(ctx, a, limit, cursor)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	out := contract.EmailProviderPage{Items: []contract.EmailProviderSummary{}, NextCursor: emailOptionalStringMapper(result.NextCursor)}
	for _, p := range result.Items {
		out.Items = append(out.Items, emailProviderSummaryResponseMapper(p))
	}
	return contract.ListEmailProviders200JSONResponse(out), nil
}
func (h *EmailHandler) GetEmailProvider(ctx context.Context, request contract.GetEmailProviderRequestObject) (contract.GetEmailProviderResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	result, err := h.service.Get(ctx, a, request.ProviderId.String())
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.GetEmailProvider200JSONResponse(emailProviderResponseMapper(result)), nil
}
func (h *EmailHandler) CreateEmailProvider(ctx context.Context, request contract.CreateEmailProviderRequestObject) (contract.CreateEmailProviderResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	b := request.Body
	if b == nil || b.Id == uuid.Nil {
		return h.failure(ctx, m.EmailValidationError{Message: "valid provider request is required"}), nil
	}
	result, err := h.service.Create(ctx, a, m.EmailProviderInput{ID: b.Id.String(), EmailSettings: m.EmailSettings{Label: b.Label, Host: b.Endpoint, Port: int(b.Port), Mailbox: b.Mailbox, Enabled: b.Enabled, IntervalMinutes: int(b.IntervalMinutes), MaxAgeDays: int(b.MaxAgeDays), PageSize: int(b.PageSize)}, Username: &b.Username, Password: b.Password})
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.CreateEmailProvider201JSONResponse(emailProviderResponseMapper(result)), nil
}
func (h *EmailHandler) UpdateEmailProvider(ctx context.Context, request contract.UpdateEmailProviderRequestObject) (contract.UpdateEmailProviderResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	b := request.Body
	if b == nil {
		return h.failure(ctx, m.EmailValidationError{Message: "request body required"}), nil
	}
	renew := b.RenewConsent != nil && *b.RenewConsent
	result, err := h.service.Update(ctx, a, m.EmailProviderInput{ID: request.ProviderId.String(), EmailSettings: m.EmailSettings{Label: b.Label, Host: b.Endpoint, Port: int(b.Port), Mailbox: b.Mailbox, Enabled: b.Enabled, IntervalMinutes: int(b.IntervalMinutes), MaxAgeDays: int(b.MaxAgeDays), PageSize: int(b.PageSize)}, Username: b.Username, Password: b.Password, ExpectedRevision: &b.ExpectedRevision, RenewConsent: renew})
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.UpdateEmailProvider200JSONResponse(emailProviderResponseMapper(result)), nil
}
func (h *EmailHandler) DeleteEmailProvider(ctx context.Context, request contract.DeleteEmailProviderRequestObject) (contract.DeleteEmailProviderResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	if err = h.service.Delete(ctx, a, request.ProviderId.String(), request.Params.ExpectedRevision); err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.DeleteEmailProvider204Response{}, nil
}
func (h *EmailHandler) TestEmailConnection(ctx context.Context, request contract.TestEmailConnectionRequestObject) (contract.TestEmailConnectionResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	b := request.Body
	if b == nil {
		return h.failure(ctx, m.EmailValidationError{Message: "request body required"}), nil
	}
	id := ""
	if b.ProviderId != nil {
		id = b.ProviderId.String()
	}
	_, err = h.service.Test(ctx, a, m.EmailTestConnection{ProviderID: id, ExpectedRevision: b.ExpectedRevision, EmailConnection: m.EmailConnection{Host: b.Endpoint, Port: int(b.Port), Mailbox: b.Mailbox}, Username: b.Username, Password: b.Password})
	var failure m.EmailFailure
	if errors.As(err, &failure) {
		return contract.TestEmailConnection200JSONResponse{CheckedAt: time.Now().UTC(), Success: false, FailureCode: emailOptionalStringMapper(failure.Code)}, nil
	}
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.TestEmailConnection200JSONResponse{CheckedAt: time.Now().UTC(), Success: true}, nil
}
func (h *EmailHandler) ListEmailRuns(ctx context.Context, request contract.ListEmailRunsRequestObject) (contract.ListEmailRunsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	limit, cursor, err := page(request.Params.Limit, request.Params.Cursor)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	query := m.EmailRunQuery{ActiveOnly: request.Params.ActiveOnly != nil && *request.Params.ActiveOnly, ProviderID: request.ProviderId.String(), Limit: limit, Cursor: cursor}
	if request.Params.Status != nil {
		query.Status = string(*request.Params.Status)
	}
	result, err := h.service.Runs(ctx, a, query)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	out := contract.EmailRunPage{Counts: emailJobCountsResponseMapper(result.Counts), Items: []contract.EmailRun{}, NextCursor: emailOptionalStringMapper(result.NextCursor)}
	for _, r := range result.Items {
		out.Items = append(out.Items, emailRunResponseMapper(r))
	}
	return contract.ListEmailRuns200JSONResponse(out), nil
}
func (h *EmailHandler) ListOwnEmailRuns(ctx context.Context, request contract.ListOwnEmailRunsRequestObject) (contract.ListOwnEmailRunsResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	limit, cursor, err := page(request.Params.Limit, request.Params.Cursor)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	query := m.EmailRunQuery{ActiveOnly: request.Params.ActiveOnly != nil && *request.Params.ActiveOnly, Limit: limit, Cursor: cursor}
	if request.Params.Status != nil {
		query.Status = string(*request.Params.Status)
	}
	result, err := h.service.Runs(ctx, a, query)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	out := contract.EmailRunPage{Counts: emailJobCountsResponseMapper(result.Counts), Items: []contract.EmailRun{}, NextCursor: emailOptionalStringMapper(result.NextCursor)}
	for _, r := range result.Items {
		out.Items = append(out.Items, emailRunResponseMapper(r))
	}
	return contract.ListOwnEmailRuns200JSONResponse(out), nil
}
func (h *EmailHandler) StartEmailRun(ctx context.Context, request contract.StartEmailRunRequestObject) (contract.StartEmailRunResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	b := request.Body
	if b == nil || b.RequestId == uuid.Nil {
		return h.failure(ctx, m.EmailValidationError{Message: "run request required"}), nil
	}
	result, err := h.service.Start(ctx, a, request.ProviderId.String(), m.EmailStartRun{RequestID: b.RequestId.String(), ExpectedRevision: b.ExpectedRevision})
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.StartEmailRun202JSONResponse(emailRunResponseMapper(result)), nil
}
func (h *EmailHandler) GetEmailRun(ctx context.Context, request contract.GetEmailRunRequestObject) (contract.GetEmailRunResponseObject, error) {
	a, err := actor(ctx)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	result, err := h.service.Run(ctx, a, request.RunId.String())
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.GetEmailRun200JSONResponse(emailRunResponseMapper(result)), nil
}
