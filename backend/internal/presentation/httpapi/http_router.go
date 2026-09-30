package httpapi

import (
	chatroutes "github.com/domabas/domabas/backend/internal/presentation/chat/routes"
	schedulerroutes "github.com/domabas/domabas/backend/internal/presentation/scheduler/routes"
	"log/slog"
	"net/http"
	"slices"
	"time"

	documentroutes "github.com/domabas/domabas/backend/internal/presentation/document/routes"
	emailroutes "github.com/domabas/domabas/backend/internal/presentation/email/routes"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	identityroutes "github.com/domabas/domabas/backend/internal/presentation/identity/routes"
	invoiceroutes "github.com/domabas/domabas/backend/internal/presentation/invoice/routes"
	paperlessroutes "github.com/domabas/domabas/backend/internal/presentation/paperless/routes"
	realtimeroutes "github.com/domabas/domabas/backend/internal/presentation/realtime/routes"
)

func NewHTTPRouter(handler *HTTPHandler, guard *transport.HTTPIdentityGuard, allowedOrigins []string, logger *slog.Logger) http.Handler {
	if guard == nil {
		panic("HTTP authentication guard is required")
	}
	requestError := func(w http.ResponseWriter, _ *http.Request, _ error) {
		transport.WriteError(w, http.StatusBadRequest, "invalid_request", "request parameters or body are invalid")
	}
	strict := contract.NewStrictHandlerWithOptions(handler, nil, contract.StrictHTTPServerOptions{
		RequestErrorHandlerFunc: requestError,
		ResponseErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, err error) {
			logger.ErrorContext(r.Context(), "HTTP response failed", "error", err)
			transport.WriteError(w, http.StatusInternalServerError, "internal_error", "an unexpected error occurred")
		},
	})
	server, documentGroups := documentroutes.Register(strict, guard)
	server, identityGroups := identityroutes.Register(server, guard, time.Now, allowedOrigins)
	server, emailGroups := emailroutes.Register(server, guard)
	server, paperlessGroups := paperlessroutes.Register(server, guard)
	server, invoiceGroups := invoiceroutes.Register(server, guard)
	server, realtimeGroups := realtimeroutes.Register(server)
	server, chatGroups := chatroutes.Register(server, guard)
	server, schedulerGroups := schedulerroutes.Register(server, guard)
	groups := append(identityGroups, documentGroups...)
	groups = append(groups, emailGroups...)
	groups = append(groups, paperlessGroups...)
	groups = append(groups, realtimeGroups...)
	groups = append(groups, invoiceGroups...)
	groups = append(groups, chatGroups...)
	groups = append(groups, schedulerGroups...)
	routes := contract.HandlerWithOptions(server, contract.StdHTTPServerOptions{
		BaseRouter: routing.NewHTTPRouter(groups...), ErrorHandlerFunc: requestError,
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.ErrorContext(r.Context(), "HTTP handler panic", "panic", recovered)
				transport.WriteError(w, http.StatusInternalServerError, "internal_error", "an unexpected error occurred")
			}
		}()
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Add("Vary", "Origin")
		origin := r.Header.Get("Origin")
		if origin != "" && slices.Contains(allowedOrigins, origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Domabas-Browser")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		routes.ServeHTTP(w, r)
	})
}
