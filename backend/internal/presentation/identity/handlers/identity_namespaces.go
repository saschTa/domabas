package handlers

import (
	"context"
	"net/http"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/domabas/domabas/backend/internal/presentation/identity/models"
)

func pagination(limit, offset *int) (int, int) {
	l, o := 50, 0
	if limit != nil {
		l = *limit
	}
	if offset != nil {
		o = *offset
	}
	return l, o
}

func (h *IdentityHandler) ListAccounts(ctx context.Context, request contract.ListAccountsRequestObject) (contract.ListAccountsResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	limit, offset := pagination(request.Params.Limit, request.Params.Offset)
	page, err := h.service.ListAccounts(ctx, p, limit, offset)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	items := make([]contract.AccountMembership, len(page.Items))
	for i, m := range page.Items {
		items[i] = identityMembershipResponseMapper(m)
	}
	return contract.ListAccounts200JSONResponse{Items: items, Total: page.Total}, nil
}
func (h *IdentityHandler) SwitchAccount(ctx context.Context, request contract.SwitchAccountRequestObject) (contract.SwitchAccountResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil {
		return h.failure(ctx, domain.IdentityValidationError("request body is required")), nil
	}
	model := models.IdentitySwitchAccountRequest{AccountID: request.Body.AccountId.String()}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	s, err := h.service.SwitchAccount(ctx, p, model.AccountID)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return models.NewIdentitySessionResponse(ctx, identitySessionResponseMapper(s), http.StatusOK), nil
}
func (h *IdentityHandler) ListClaims(ctx context.Context, _ contract.ListClaimsRequestObject) (contract.ListClaimsResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if p.MustChangePassword {
		return h.failure(ctx, domain.ErrPasswordChange), nil
	}
	items := make([]contract.Claim, 0)
	for _, claim := range domain.ClaimCatalog() {
		roles := make([]string, len(claim.Roles))
		for i, role := range claim.Roles {
			roles[i] = string(role)
		}
		items = append(items, contract.Claim{Id: string(claim.ID), Label: claim.Label, Scope: contract.ClaimScope(claim.Scope), Roles: roles})
	}
	return contract.ListClaims200JSONResponse{Items: items}, nil
}
func (h *IdentityHandler) CreateInvitation(ctx context.Context, request contract.CreateInvitationRequestObject) (contract.CreateInvitationResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil {
		return h.failure(ctx, domain.IdentityValidationError("request body is required")), nil
	}
	model := models.IdentityInvitationRequest{Email: request.Body.Email, Role: string(request.Body.Role), Claims: request.Body.Claims}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	result, err := h.service.CreateInvitation(ctx, p, model.Email, domain.IdentityRole(model.Role), identityPermissionsMapper(model.Claims))
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.CreateInvitation201JSONResponse{Code: result.Code, Invitation: identityInvitationResponseMapper(result.Invitation)}, nil
}
func (h *IdentityHandler) ListInvitations(ctx context.Context, request contract.ListInvitationsRequestObject) (contract.ListInvitationsResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	limit, offset := pagination(request.Params.Limit, request.Params.Offset)
	page, err := h.service.ListInvitations(ctx, p, limit, offset)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	items := make([]contract.Invitation, len(page.Items))
	for i, v := range page.Items {
		items[i] = identityInvitationResponseMapper(v)
	}
	return contract.ListInvitations200JSONResponse{Items: items, Total: page.Total}, nil
}
func (h *IdentityHandler) RevokeInvitation(ctx context.Context, request contract.RevokeInvitationRequestObject) (contract.RevokeInvitationResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if err := h.service.RevokeInvitation(ctx, p, request.Id.String()); err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.RevokeInvitation204Response{}, nil
}
func (h *IdentityHandler) AcceptInvitation(ctx context.Context, request contract.AcceptInvitationRequestObject) (contract.AcceptInvitationResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil || request.Body.Code == nil {
		return h.failure(ctx, domain.IdentityValidationError("code is required")), nil
	}
	model := models.IdentityAcceptInvitationRequest{Code: *request.Body.Code}
	m, err := h.service.AcceptInvitation(ctx, p, model.Code)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.AcceptInvitation201JSONResponse(identityMembershipResponseMapper(m)), nil
}
func (h *IdentityHandler) ListSystemUsers(ctx context.Context, request contract.ListSystemUsersRequestObject) (contract.ListSystemUsersResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	limit, offset := pagination(request.Params.Limit, request.Params.Offset)
	page, err := h.service.ListSystemUsers(ctx, p, limit, offset)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	items := make([]contract.SystemUser, len(page.Items))
	for i, v := range page.Items {
		items[i] = identitySystemUserResponseMapper(v)
	}
	return contract.ListSystemUsers200JSONResponse{Items: items, Total: page.Total, AdminCount: page.AdminCount}, nil
}
func (h *IdentityHandler) UpdateSystemUser(ctx context.Context, request contract.UpdateSystemUserRequestObject) (contract.UpdateSystemUserResponseObject, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	if request.Body == nil {
		return h.failure(ctx, domain.IdentityValidationError("request body is required")), nil
	}
	model := models.IdentitySystemRoleRequest{Role: string(request.Body.Role)}
	if err := model.Validate(); err != nil {
		return h.failure(ctx, err), nil
	}
	u, err := h.service.UpdateSystemUser(ctx, p, request.Id.String(), domain.IdentityRole(model.Role))
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.UpdateSystemUser200JSONResponse(identitySystemUserResponseMapper(u)), nil
}
