package httpapi

import (
	"context"
	chat "github.com/domabas/domabas/backend/internal/presentation/chat/handlers"
	scheduler "github.com/domabas/domabas/backend/internal/presentation/scheduler/handlers"
	"time"

	document "github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	email "github.com/domabas/domabas/backend/internal/presentation/email/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	identity "github.com/domabas/domabas/backend/internal/presentation/identity/handlers"
	invoice "github.com/domabas/domabas/backend/internal/presentation/invoice/handlers"
	paperless "github.com/domabas/domabas/backend/internal/presentation/paperless/handlers"
	realtime "github.com/domabas/domabas/backend/internal/presentation/realtime/handlers"
)

type HTTPReadinessProbe interface{ Ping(context.Context) error }

type invoiceHandler = invoice.InvoiceHandler
type documentHandler = document.DocumentHandler
type identityHandler = identity.IdentityHandler
type emailHandler = email.EmailHandler
type realtimeHandler = realtime.RealtimeHandler
type paperlessHandler = paperless.PaperlessHandler
type chatHandler = chat.ChatHandler
type schedulerHandler = scheduler.SchedulerHandler

type HTTPHandler struct {
	*schedulerHandler
	*chatHandler
	*invoiceHandler
	*paperlessHandler
	*documentHandler
	*identityHandler
	*emailHandler
	*realtimeHandler
	probe HTTPReadinessProbe
}

func (handler *HTTPHandler) WithChat(chat *chat.ChatHandler) *HTTPHandler {
	handler.chatHandler = chat
	return handler
}

func (handler *HTTPHandler) WithScheduler(scheduler *scheduler.SchedulerHandler) *HTTPHandler {
	handler.schedulerHandler = scheduler
	return handler
}

var _ contract.StrictServerInterface = (*HTTPHandler)(nil)

func NewHTTPHandler(documents *document.DocumentHandler, identities *identity.IdentityHandler, email *email.EmailHandler, probe HTTPReadinessProbe, realtime *realtime.RealtimeHandler, invoices *invoice.InvoiceHandler, imports ...*paperless.PaperlessHandler) *HTTPHandler {
	h := &HTTPHandler{invoiceHandler: invoices, documentHandler: documents, identityHandler: identities, emailHandler: email, realtimeHandler: realtime, probe: probe}
	if len(imports) > 0 {
		h.paperlessHandler = imports[0]
	}
	return h
}

func (handler *HTTPHandler) Health(context.Context, contract.HealthRequestObject) (contract.HealthResponseObject, error) {
	return contract.Health200JSONResponse{Status: contract.Ok}, nil
}

func (handler *HTTPHandler) Readiness(ctx context.Context, _ contract.ReadinessRequestObject) (contract.ReadinessResponseObject, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := handler.probe.Ping(ctx); err != nil {
		return contract.Readiness503JSONResponse{UnavailableJSONResponse: contract.UnavailableJSONResponse{Code: "unavailable", Message: "a required service is unavailable"}}, nil
	}
	return contract.Readiness200JSONResponse{Status: contract.Ok}, nil
}
