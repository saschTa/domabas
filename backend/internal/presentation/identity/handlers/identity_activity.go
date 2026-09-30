package handlers

import (
	"context"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

type IdentityActivityService interface {
	PersonalActivity(context.Context, domain.IdentityPrincipal, domain.IdentityActivityPageRequest) (domain.PersonalActivity, error)
}

func (h *IdentityHandler) GetPersonalActivity(ctx context.Context, request contract.GetPersonalActivityRequestObject) (contract.GetPersonalActivityResponseObject, error) {
	principal, ok := transport.Principal(ctx)
	if !ok {
		return h.failure(ctx, domain.ErrUnauthorized), nil
	}
	page := domain.IdentityActivityPageRequest{}
	if request.Params.ActiveCursor != nil {
		page.ActiveCursor = *request.Params.ActiveCursor
	}
	if request.Params.FinishedCursor != nil {
		page.FinishedCursor = *request.Params.FinishedCursor
	}
	activity, err := h.activity.PersonalActivity(ctx, principal, page)
	if err != nil {
		return h.failure(ctx, err), nil
	}
	return contract.GetPersonalActivity200JSONResponse{Active: identityActivityResponseMapper(activity.Active), Finished: identityActivityResponseMapper(activity.Finished), ActiveLimit: contract.N20, ActiveTruncated: activity.ActiveTruncated, ActiveNextCursor: identityActivityCursorMapper(activity.ActiveNextCursor), FinishedNextCursor: identityActivityCursorMapper(activity.FinishedNextCursor), GeneratedAt: activity.GeneratedAt}, nil
}
