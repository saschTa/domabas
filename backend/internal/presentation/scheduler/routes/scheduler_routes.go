package routes

import (
	"bytes"
	"io"
	"net/http"

	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/domabas/domabas/backend/internal/presentation/scheduler/models"
)

type validatedSchedulerServer struct{ contract.ServerInterface }

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &validatedSchedulerServer{server}, []routing.HTTPRouteGroup{{Prefix: "/api/v1/system/workload-settings", Middleware: []routing.HTTPMiddleware{guard.Require(identity.SystemWorkloadsManage)}}}
}

func (s *validatedSchedulerServer) UpdateWorkloadSettings(w http.ResponseWriter, r *http.Request) {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return
	}
	if models.ValidateSettings(body) != nil {
		transport.WriteError(w, 400, "invalid_settings", "provide valid resource limits and the current settings revision")
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	s.ServerInterface.UpdateWorkloadSettings(w, r)
}
