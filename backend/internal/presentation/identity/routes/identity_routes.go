package routes

import (
	"bytes"
	"io"
	"net/http"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/oapi-codegen/runtime/types"
)

func noStore(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}
func groups(guard *transport.HTTPIdentityGuard, browser routing.HTTPMiddleware) []routing.HTTPRouteGroup {
	return []routing.HTTPRouteGroup{{Prefix: "/api/v1/auth", Middleware: []routing.HTTPMiddleware{noStore, browser}, Children: []routing.HTTPRouteGroup{
		{Prefix: "/session", Middleware: []routing.HTTPMiddleware{guard.Require("")}}, {Prefix: "/password", Middleware: []routing.HTTPMiddleware{guard.Require("")}},
		{Prefix: "/accounts", Middleware: []routing.HTTPMiddleware{guard.RequireCompleteSession()}}, {Prefix: "/switch-account", Middleware: []routing.HTTPMiddleware{guard.RequireCompleteSession()}},
		{Prefix: "/claims", Middleware: []routing.HTTPMiddleware{guard.RequireCompleteSession()}}, {Prefix: "/accept-invitation", Middleware: []routing.HTTPMiddleware{guard.RequireCompleteSession()}},
		{Prefix: "/activity", Middleware: []routing.HTTPMiddleware{guard.RequireCompleteSession()}},
	}}, {Prefix: "/api/v1/account", Middleware: []routing.HTTPMiddleware{guard.Require(domain.UsersManage)}}, {Prefix: "/api/v1/system/users", Middleware: []routing.HTTPMiddleware{guard.Require(domain.SystemUsersManage)}}}
}

type validatedIdentityServer struct {
	contract.ServerInterface
	limiter *identityRateLimiter
}

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard, now func() time.Time, allowedOrigins []string) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &validatedIdentityServer{ServerInterface: server, limiter: newIdentityRateLimiter(now)}, groups(guard, browserSessions(allowedOrigins, now))
}
func (s *validatedIdentityServer) validate(w http.ResponseWriter, r *http.Request, operation string) bool {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return false
	}
	email, err := decodeFields(body, operation)
	if err != nil {
		writeError(w, 400, "invalid_request", err.Error())
		return false
	}
	if operation == "password" || operation == "accept_invitation" {
		principal, _ := transport.Principal(r.Context())
		email = principal.Email
	}
	if (operation == "register" || operation == "login" || operation == "password" || operation == "create_member" || operation == "create_invitation" || operation == "accept_invitation") && !s.limiter.check(w, r, operation, email) {
		return false
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	return true
}
func (s *validatedIdentityServer) Register(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "register") {
		s.ServerInterface.Register(w, r)
	}
}
func (s *validatedIdentityServer) Login(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "login") {
		s.ServerInterface.Login(w, r)
	}
}
func (s *validatedIdentityServer) ChangePassword(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "password") {
		s.ServerInterface.ChangePassword(w, r)
	}
}
func (s *validatedIdentityServer) CreateAccountUser(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "create_member") {
		s.ServerInterface.CreateAccountUser(w, r)
	}
}
func (s *validatedIdentityServer) UpdateAccountUser(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if s.validate(w, r, "update_member") {
		s.ServerInterface.UpdateAccountUser(w, r, id)
	}
}
func (s *validatedIdentityServer) SwitchAccount(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "switch_account") {
		s.ServerInterface.SwitchAccount(w, r)
	}
}
func (s *validatedIdentityServer) CreateInvitation(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "create_invitation") {
		s.ServerInterface.CreateInvitation(w, r)
	}
}
func (s *validatedIdentityServer) AcceptInvitation(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "accept_invitation") {
		s.ServerInterface.AcceptInvitation(w, r)
	}
}
func (s *validatedIdentityServer) UpdateSystemUser(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if s.validate(w, r, "system_role") {
		s.ServerInterface.UpdateSystemUser(w, r, id)
	}
}
func writeError(w http.ResponseWriter, status int, code, message string) {
	transport.WriteError(w, status, code, message)
}
