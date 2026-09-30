package routes

import (
	"bytes"
	"io"
	"net/http"

	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/domabas/domabas/backend/internal/presentation/paperless/models"
	"github.com/oapi-codegen/runtime/types"
)

type validatedPaperlessServer struct{ contract.ServerInterface }

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &validatedPaperlessServer{server}, []routing.HTTPRouteGroup{
		{Prefix: "/api/v1/paperless-import", Middleware: []routing.HTTPMiddleware{guard.RequireAll(identity.PaperlessImport, identity.DocumentsRead, identity.DocumentsUpload)}},
		{Prefix: "/api/v1/system/paperless-import", Middleware: []routing.HTTPMiddleware{guard.Require(identity.SystemPaperlessManage)}},
	}
}

func (s *validatedPaperlessServer) UpdatePaperlessSettings(w http.ResponseWriter, r *http.Request) {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return
	}
	if models.ValidateSettings(body) != nil {
		transport.WriteError(w, 400, "invalid_settings", "provide concurrency from 1 to 10 and the current settings revision")
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	s.ServerInterface.UpdatePaperlessSettings(w, r)
}
func (s *validatedPaperlessServer) StartPaperlessRun(w http.ResponseWriter, r *http.Request) {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return
	}
	if models.Validate(body) != nil {
		transport.WriteError(w, 400, "invalid_request", "provide a request ID, configured server URL and API token")
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	s.ServerInterface.StartPaperlessRun(w, r)
}
func (s *validatedPaperlessServer) CancelPaperlessRun(w http.ResponseWriter, r *http.Request, id types.UUID) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1))
	if err != nil || len(body) > 0 {
		transport.WriteError(w, 400, "invalid_request", "cancellation does not accept a body")
		return
	}
	s.ServerInterface.CancelPaperlessRun(w, r, id)
}
