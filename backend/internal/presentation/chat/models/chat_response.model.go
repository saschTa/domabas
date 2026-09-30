package models

import (
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"net/http"
)

type ChatErrorResponse struct {
	Status        int
	Code, Message string
}

func (r ChatErrorResponse) write(w http.ResponseWriter) error {
	transport.WriteError(w, r.Status, r.Code, r.Message)
	return nil
}
func (r ChatErrorResponse) VisitGetChatConfigurationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitGetChatAdminConfigurationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitUpdateChatConfigurationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitListChatModelsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitGetChatModelContextResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitCreateChatConversationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitListChatConversationsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitGetChatConversationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitDeleteChatConversationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitListChatMessagesResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitSendChatMessageResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r ChatErrorResponse) VisitCancelChatTurnResponse(w http.ResponseWriter) error {
	return r.write(w)
}
