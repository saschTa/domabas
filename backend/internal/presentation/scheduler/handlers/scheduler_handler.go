package handlers

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	r "github.com/domabas/domabas/backend/internal/presentation/scheduler/models"
)

type SchedulerHTTPService interface {
	Settings(context.Context, m.SchedulerActor) (m.SchedulerSettings, error)
	UpdateSettings(context.Context, m.SchedulerActor, m.SchedulerSettingsUpdate) (m.SchedulerSettings, error)
}

type SchedulerHandler struct{ service SchedulerHTTPService }

func NewSchedulerHandler(service SchedulerHTTPService) *SchedulerHandler {
	return &SchedulerHandler{service: service}
}

func (h *SchedulerHandler) actor(ctx context.Context) (m.SchedulerActor, error) {
	principal, ok := transport.Principal(ctx)
	if !ok {
		return m.SchedulerActor{}, m.ErrUnauthorized
	}
	if h == nil || h.service == nil {
		return m.SchedulerActor{}, errors.New("workload settings unavailable")
	}
	return m.SchedulerActor{AccountID: principal.AccountID, UserID: principal.UserID, SessionDigest: principal.SessionDigest, CredentialRevision: principal.CredentialRevision}, nil
}

func schedulerFailure(err error) r.SchedulerErrorResponse {
	var invalid m.SchedulerValidationError
	switch {
	case errors.As(err, &invalid):
		return r.SchedulerErrorResponse{Status: 400, Code: "invalid_settings", Message: "Provide valid resource limits and the current settings revision."}
	case errors.Is(err, m.ErrUnauthorized):
		return r.SchedulerErrorResponse{Status: 401, Code: "unauthorized", Message: "Sign in again."}
	case errors.Is(err, m.ErrForbidden):
		return r.SchedulerErrorResponse{Status: 403, Code: "forbidden", Message: "System administrator permission is required."}
	case errors.Is(err, m.ErrConflict):
		return r.SchedulerErrorResponse{Status: 409, Code: "conflict", Message: "Workload settings changed. Reload and save again."}
	default:
		return r.SchedulerErrorResponse{Status: 503, Code: "unavailable", Message: "Workload settings could not be loaded. Try again."}
	}
}

func (h *SchedulerHandler) GetWorkloadSettings(ctx context.Context, _ contract.GetWorkloadSettingsRequestObject) (contract.GetWorkloadSettingsResponseObject, error) {
	actor, err := h.actor(ctx)
	if err != nil {
		return schedulerFailure(err), nil
	}
	settings, err := h.service.Settings(ctx, actor)
	if err != nil {
		return schedulerFailure(err), nil
	}
	return contract.GetWorkloadSettings200JSONResponse(schedulerSettingsResponseMapper(settings)), nil
}

func (h *SchedulerHandler) UpdateWorkloadSettings(ctx context.Context, request contract.UpdateWorkloadSettingsRequestObject) (contract.UpdateWorkloadSettingsResponseObject, error) {
	actor, err := h.actor(ctx)
	if err != nil {
		return schedulerFailure(err), nil
	}
	if request.Body == nil {
		return schedulerFailure(m.SchedulerValidationError{}), nil
	}
	update := m.SchedulerSettingsUpdate{ExpectedRevision: request.Body.ExpectedRevision, Resources: make([]m.SchedulerResourceUpdate, 0, len(request.Body.Resources))}
	for _, resource := range request.Body.Resources {
		update.Resources = append(update.Resources, m.SchedulerResourceUpdate{ID: resource.Id, Limit: resource.Limit})
	}
	settings, err := h.service.UpdateSettings(ctx, actor, update)
	if err != nil {
		return schedulerFailure(err), nil
	}
	return contract.UpdateWorkloadSettings200JSONResponse(schedulerSettingsResponseMapper(settings)), nil
}
