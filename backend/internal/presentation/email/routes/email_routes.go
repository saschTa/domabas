package routes

import (
	"bytes"
	"io"
	"net/http"
	"slices"
	"time"

	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/email/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/oapi-codegen/runtime/types"
)

type validatedEmailServer struct{ contract.ServerInterface }

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	groups := []routing.HTTPRouteGroup{}
	for _, prefix := range []string{"/api/v1/email-capabilities", "/api/v1/email-providers", "/api/v1/email-runs", "/api/v1/email-connection-tests"} {
		group := routing.HTTPRouteGroup{Prefix: prefix, Middleware: []routing.HTTPMiddleware{guard.Require(identity.IdentityPermission("email:manage"))}}
		if prefix == "/api/v1/email-connection-tests" {
			group.Timeout = 20 * time.Second
		}
		groups = append(groups, group)
	}
	return &validatedEmailServer{ServerInterface: server}, groups
}
func (s *validatedEmailServer) validate(w http.ResponseWriter, r *http.Request, operation string) bool {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return false
	}
	if err := models.ValidateObject(body, operation); err != nil {
		transport.WriteError(w, 400, "invalid_request", err.Error())
		return false
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	return true
}
func (s *validatedEmailServer) CreateEmailProvider(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "create") {
		s.ServerInterface.CreateEmailProvider(w, r)
	}
}
func (s *validatedEmailServer) UpdateEmailProvider(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if s.validate(w, r, "update") {
		s.ServerInterface.UpdateEmailProvider(w, r, id)
	}
}
func (s *validatedEmailServer) TestEmailConnection(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "test") {
		s.ServerInterface.TestEmailConnection(w, r)
	}
}
func (s *validatedEmailServer) StartEmailRun(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if s.validate(w, r, "run") {
		s.ServerInterface.StartEmailRun(w, r, id)
	}
}
func validQuery(w http.ResponseWriter, r *http.Request, allowed ...string) bool {
	for name, values := range r.URL.Query() {
		if !slices.Contains(allowed, name) || len(values) != 1 || values[0] == "" {
			transport.WriteError(w, 400, "invalid_request", "query fields must be single valid values")
			return false
		}
	}
	return true
}
func (s *validatedEmailServer) ListEmailProviders(w http.ResponseWriter, r *http.Request, p contract.ListEmailProvidersParams) {
	if validQuery(w, r, "limit", "cursor") {
		s.ServerInterface.ListEmailProviders(w, r, p)
	}
}
func (s *validatedEmailServer) ListEmailRuns(w http.ResponseWriter, r *http.Request, id types.UUID, p contract.ListEmailRunsParams) {
	if validQuery(w, r, "limit", "cursor", "status", "activeOnly") {
		s.ServerInterface.ListEmailRuns(w, r, id, p)
	}
}
func (s *validatedEmailServer) ListOwnEmailRuns(w http.ResponseWriter, r *http.Request, p contract.ListOwnEmailRunsParams) {
	if validQuery(w, r, "limit", "cursor", "status", "activeOnly") {
		s.ServerInterface.ListOwnEmailRuns(w, r, p)
	}
}
func (s *validatedEmailServer) DeleteEmailProvider(w http.ResponseWriter, r *http.Request, id types.UUID, p contract.DeleteEmailProviderParams) {
	if !validQuery(w, r, "expectedRevision") {
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1))
	if err != nil || len(body) > 0 {
		transport.WriteError(w, 400, "invalid_request", "delete does not accept a body")
		return
	}
	s.ServerInterface.DeleteEmailProvider(w, r, id, p)
}
