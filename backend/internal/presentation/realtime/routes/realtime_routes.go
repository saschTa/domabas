package routes

import (
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/realtime/models"
)

type realtimeServer struct{ contract.ServerInterface }

func Register(next contract.ServerInterface) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &realtimeServer{next}, []routing.HTTPRouteGroup{{Prefix: "/api/v1/realtime", Streaming: true}}
}
func (s *realtimeServer) OpenRealtime(w http.ResponseWriter, r *http.Request) {
	s.ServerInterface.OpenRealtime(w, r.WithContext(models.WithRequest(r.Context(), r)))
}
