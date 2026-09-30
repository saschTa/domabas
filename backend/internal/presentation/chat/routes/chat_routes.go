package routes

import (
	"bytes"
	"io"
	"net/http"

	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/chat/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/oapi-codegen/runtime/types"
)

type validatedChatServer struct{ contract.ServerInterface }

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &validatedChatServer{server}, []routing.HTTPRouteGroup{
		{Prefix: "/api/v1/chat", Middleware: []routing.HTTPMiddleware{guard.Require(identity.ChatUse), chatQuery}},
		{Prefix: "/api/v1/system/chat", Middleware: []routing.HTTPMiddleware{guard.Require(identity.SystemChatManage), chatQuery}},
	}
}
func chatQuery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		modelContext := r.URL.Path == "/api/v1/system/chat/model-context"
		for name, values := range r.URL.Query() {
			allowed := name == "limit" || name == "cursor" || name == "offset"
			if modelContext {
				allowed = name == "model"
			}
			if !allowed || len(values) != 1 || values[0] == "" {
				transport.WriteError(w, 400, "invalid_request", "Use single nonempty supported query parameters.")
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
func (s *validatedChatServer) validate(w http.ResponseWriter, r *http.Request, operation string) bool {
	body, ok := transport.ReadJSONLimit(w, r, 64*1024)
	if !ok {
		return false
	}
	if models.ValidateChatObject(body, operation) != nil {
		transport.WriteError(w, 400, "invalid_request", "Provide valid chat fields without duplicates or unknown properties.")
		return false
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	return true
}
func (s *validatedChatServer) CreateChatConversation(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "create") {
		s.ServerInterface.CreateChatConversation(w, r)
	}
}
func (s *validatedChatServer) SendChatMessage(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if s.validate(w, r, "send") {
		s.ServerInterface.SendChatMessage(w, r, id)
	}
}
func (s *validatedChatServer) UpdateChatConfiguration(w http.ResponseWriter, r *http.Request) {
	if s.validate(w, r, "settings") {
		s.ServerInterface.UpdateChatConfiguration(w, r)
	}
}
func (s *validatedChatServer) CancelChatTurn(w http.ResponseWriter, r *http.Request, id, turn types.UUID) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1))
	if err != nil || len(body) > 0 {
		transport.WriteError(w, 400, "invalid_request", "Cancellation does not accept a body.")
		return
	}
	s.ServerInterface.CancelChatTurn(w, r, id, turn)
}
