package handlers

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/domabas/domabas/backend/internal/presentation/identity/models"
)

type IdentityHandler struct {
	service  IdentityService
	activity IdentityActivityService
	logger   *slog.Logger
}

func NewIdentityHandler(service IdentityService, activity IdentityActivityService, logger *slog.Logger) *IdentityHandler {
	return &IdentityHandler{service: service, activity: activity, logger: logger}
}
func (h *IdentityHandler) failure(ctx context.Context, err error) models.IdentityErrorResponse {
	status, code, message := 500, "internal_error", "an unexpected error occurred"
	var validation domain.IdentityValidationError
	switch {
	case errors.As(err, &validation):
		status = 400
		code, message = "invalid_request", err.Error()
	case errors.Is(err, domain.ErrCredentials):
		status = 401
		code, message = "invalid_credentials", "email or password is incorrect"
	case errors.Is(err, domain.ErrCurrentPassword):
		status = 400
		code, message = "invalid_credentials", "current password is incorrect"
	case errors.Is(err, domain.ErrUnauthorized):
		status = 401
		code, message = "unauthorized", "a valid session is required"
	case errors.Is(err, domain.ErrForbidden):
		status = 403
		code, message = "forbidden", "permission denied"
	case errors.Is(err, domain.ErrPasswordChange):
		status = 403
		code, message = "password_change_required", "change your password before continuing"
	case errors.Is(err, domain.ErrNotFound):
		status = 404
		code, message = "not_found", "the requested resource is unavailable"
	case errors.Is(err, domain.ErrConflict):
		status = 409
		code, message = "conflict", err.Error()
	case errors.Is(err, domain.ErrActivityUnavailable):
		status = 503
		code, message = "unavailable", "personal activity is temporarily unavailable"
	default:
		h.logger.ErrorContext(ctx, "identity operation failed", "error", err)
	}
	return models.NewIdentityErrorResponse(status, code, message)
}

func (h *IdentityHandler) Register(ctx context.Context, request contract.RegisterRequestObject) (contract.RegisterResponseObject, error) {
	if request.Body == nil || request.Body.Password == nil {
		return h.failure(ctx, domain.IdentityValidationError("password is required")), nil
	}
	model := models.IdentityRegistrationRequest{AccountName: request.Body.AccountName, Email: request.Body.Email, Password: *request.Body.Password}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	s, err := h.service.Register(ctx, model.AccountName, model.Email, model.Password)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return models.NewIdentitySessionResponse(ctx, identitySessionResponseMapper(s), http.StatusCreated), nil
}
func (h *IdentityHandler) Login(ctx context.Context, request contract.LoginRequestObject) (contract.LoginResponseObject, error) {
	if request.Body == nil || request.Body.Password == nil {
		return h.failure(ctx, domain.IdentityValidationError("password is required")), nil
	}
	model := models.IdentityLoginRequest{Email: request.Body.Email, Password: *request.Body.Password}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	s, err := h.service.Login(ctx, model.Email, model.Password)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return models.NewIdentitySessionResponse(ctx, identitySessionResponseMapper(s), http.StatusOK), nil
}
func (h *IdentityHandler) RestoreSession(ctx context.Context, _ contract.RestoreSessionRequestObject) (contract.RestoreSessionResponseObject, error) {
	request := models.CurrentSessionRequest(ctx)
	if request.Browser && !request.HasCredential {
		return contract.RestoreSession204Response{}, nil
	}
	session, err := h.service.RestoreSession(ctx, request.Token)
	if err != nil {
		response := h.failure(ctx, err)
		if errors.Is(err, domain.ErrUnauthorized) {
			response = response.WithCookie(models.BrowserCookie(ctx, "", nil))
		}
		return response, nil
	}
	return models.NewIdentitySessionResponse(ctx, identitySessionResponseMapper(session), http.StatusOK), nil
}
func (h *IdentityHandler) CurrentIdentity(ctx context.Context, _ contract.CurrentIdentityRequestObject) (contract.CurrentIdentityResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	return contract.CurrentIdentity200JSONResponse(identityResponseMapper(p)), nil
}
func (h *IdentityHandler) Logout(ctx context.Context, _ contract.LogoutRequestObject) (contract.LogoutResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if err := h.service.Logout(ctx, p); err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.Logout204Response{}, nil
}
func (h *IdentityHandler) ChangePassword(ctx context.Context, request contract.ChangePasswordRequestObject) (contract.ChangePasswordResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil || request.Body.CurrentPassword == nil || request.Body.NewPassword == nil {
		return h.failure(ctx, domain.IdentityValidationError("password fields are required")), nil
	}
	model := models.IdentityPasswordRequest{CurrentPassword: *request.Body.CurrentPassword, NewPassword: *request.Body.NewPassword}
	if err := model.Validate(p.Email); err != nil {
		return h.failure(ctx, err), nil
	}
	if err := h.service.ChangePassword(ctx, p, model.CurrentPassword, model.NewPassword); err != nil {
		return h.failure(ctx, err), nil
	}
	return models.IdentityPasswordChangedResponse{Cookie: models.BrowserCookie(ctx, "", nil)}, nil
}
func (h *IdentityHandler) CreateAccountUser(ctx context.Context, request contract.CreateAccountUserRequestObject) (contract.CreateAccountUserResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil || request.Body.Password == nil {
		return h.failure(ctx, domain.IdentityValidationError("password is required")), nil
	}
	model := models.IdentityCreateMemberRequest{Email: request.Body.Email, Password: *request.Body.Password, Role: string(request.Body.Role), Claims: request.Body.Claims}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	m, err := h.service.CreateMember(ctx, p, model.Email, model.Password, domain.IdentityRole(model.Role), identityPermissionsMapper(model.Claims))
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.CreateAccountUser201JSONResponse(identityMemberResponseMapper(m)), nil
}
func (h *IdentityHandler) UpdateAccountUser(ctx context.Context, request contract.UpdateAccountUserRequestObject) (contract.UpdateAccountUserResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil {
		return h.failure(ctx, domain.IdentityValidationError("request body is required")), nil
	}
	model := models.IdentityUpdateMemberRequest{Role: string(request.Body.Role), Enabled: request.Body.Enabled, Claims: request.Body.Claims}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	m, err := h.service.UpdateMember(ctx, p, request.Id.String(), domain.IdentityRole(model.Role), identityPermissionsMapper(model.Claims), model.Enabled)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.UpdateAccountUser200JSONResponse(identityMemberResponseMapper(m)), nil
}
func (h *IdentityHandler) ListAccountUsers(ctx context.Context, request contract.ListAccountUsersRequestObject) (contract.ListAccountUsersResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	limit, offset := 50, 0
	if request.Params.Limit != nil {
		limit = *request.Params.Limit
	}
	if request.Params.Offset != nil {
		offset = *request.Params.Offset
	}
	page, err := h.service.ListMembers(ctx, p, limit, offset)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	items := make([]contract.AccountUser, 0, len(page.Items))
	for _, member := range page.Items {
		items = append(items, identityMemberResponseMapper(member))
	}
	return contract.ListAccountUsers200JSONResponse{Items: items, Total: page.Total}, nil
}
