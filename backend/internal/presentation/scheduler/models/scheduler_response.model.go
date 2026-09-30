package models

import (
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"net/http"
)

type SchedulerErrorResponse struct {
	Status        int
	Code, Message string
}

func (r SchedulerErrorResponse) VisitGetWorkloadSettingsResponse(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}

func (r SchedulerErrorResponse) VisitUpdateWorkloadSettingsResponse(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}
