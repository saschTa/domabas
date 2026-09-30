package handlers

import (
	"context"
	"errors"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	r "github.com/domabas/domabas/backend/internal/presentation/chat/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/google/uuid"
)

type ChatHTTPService interface {
	Configuration(context.Context, m.ChatActor, bool) (m.ChatConfiguration, error)
	UpdateConfiguration(context.Context, m.ChatActor, m.ChatConfigurationUpdate) (m.ChatConfiguration, error)
	Conversations(context.Context, m.ChatActor, m.ChatPageRequest) (m.ChatConversationPage, error)
	CreateConversation(context.Context, m.ChatActor, string) (m.ChatConversation, error)
	Conversation(context.Context, m.ChatActor, string) (m.ChatConversation, error)
	DeleteConversation(context.Context, m.ChatActor, string) error
	Messages(context.Context, m.ChatActor, string, m.ChatPageRequest) (m.ChatMessagePage, error)
	Send(context.Context, m.ChatActor, string, m.ChatSendInput) (m.ChatSendResult, error)
	Cancel(context.Context, m.ChatActor, string, string) (m.ChatMessage, error)
	Models(context.Context, m.ChatActor, int, int) (m.ChatModelPage, error)
	ModelContext(context.Context, m.ChatActor, string) (m.ChatModelContext, error)
}
type ChatHandler struct{ service ChatHTTPService }

func NewChatHandler(service ChatHTTPService) *ChatHandler { return &ChatHandler{service: service} }
func (h *ChatHandler) actor(ctx context.Context) (m.ChatActor, error) {
	p, ok := transport.Principal(ctx)
	if !ok {
		return m.ChatActor{}, m.ErrUnauthorized
	}
	if h == nil || h.service == nil {
		return m.ChatActor{}, errors.New("chat unavailable")
	}
	return m.ChatActor{AccountID: p.AccountID, UserID: p.UserID, SessionDigest: p.SessionDigest, CredentialRevision: p.CredentialRevision}, nil
}
func chatFailure(err error) r.ChatErrorResponse {
	var validation m.ChatValidationError
	switch {
	case errors.As(err, &validation):
		return r.ChatErrorResponse{Status: 400, Code: "invalid_request", Message: "Check the chat request and try again."}
	case errors.Is(err, m.ErrUnauthorized):
		return r.ChatErrorResponse{Status: 401, Code: "unauthorized", Message: "Sign in again."}
	case errors.Is(err, m.ErrForbidden):
		return r.ChatErrorResponse{Status: 403, Code: "forbidden", Message: "This action is not permitted."}
	case errors.Is(err, m.ErrNotFound):
		return r.ChatErrorResponse{Status: 404, Code: "not_found", Message: "Conversation or reply not found."}
	case errors.Is(err, m.ErrConflict):
		return r.ChatErrorResponse{Status: 409, Code: "conflict", Message: "Chat state changed. Refresh before trying again."}
	case errors.Is(err, m.ErrDisabled):
		return r.ChatErrorResponse{Status: 409, Code: "chat_disabled", Message: "AI chat is disabled by an administrator."}
	case errors.Is(err, m.ErrBusy):
		return r.ChatErrorResponse{Status: 429, Code: "overloaded", Message: "The chat queue is full. Try again shortly."}
	}
	return r.ChatErrorResponse{Status: 503, Code: "unavailable", Message: "Chat state could not be confirmed. Retry using the same request."}
}
func (h *ChatHandler) GetChatConfiguration(ctx context.Context, _ contract.GetChatConfigurationRequestObject) (contract.GetChatConfigurationResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.Configuration(ctx, a, false)
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.GetChatConfiguration200JSONResponse{Enabled: v.Enabled, Provider: contract.ChatConfigurationSummaryProvider(v.Provider), Model: v.Model, Revision: v.Revision}, nil
}
func (h *ChatHandler) GetChatAdminConfiguration(ctx context.Context, _ contract.GetChatAdminConfigurationRequestObject) (contract.GetChatAdminConfigurationResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.Configuration(ctx, a, true)
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.GetChatAdminConfiguration200JSONResponse(chatConfigurationMapper(v)), nil
}
func (h *ChatHandler) UpdateChatConfiguration(ctx context.Context, q contract.UpdateChatConfigurationRequestObject) (contract.UpdateChatConfigurationResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	b := q.Body
	if b == nil {
		return chatFailure(m.ChatValidationError{}), nil
	}
	v, err := h.service.UpdateConfiguration(ctx, a, m.ChatConfigurationUpdate{ThinkingEnabled: b.ThinkingEnabled, ExpectedRevision: b.ExpectedRevision, ContextLength: b.ContextLength, Enabled: b.Enabled, Provider: string(b.Provider), Model: b.Model, BaseURL: b.BaseUrl, APIKey: b.ApiKey, ClearAPIKey: b.ClearApiKey != nil && *b.ClearApiKey})
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.UpdateChatConfiguration200JSONResponse(chatConfigurationMapper(v)), nil
}
func (h *ChatHandler) GetChatModelContext(ctx context.Context, q contract.GetChatModelContextRequestObject) (contract.GetChatModelContextResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.ModelContext(ctx, a, q.Params.Model)
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.GetChatModelContext200JSONResponse{Model: v.Model, MaxContextLength: v.MaxContextLength}, nil
}
func (h *ChatHandler) ListChatModels(ctx context.Context, q contract.ListChatModelsRequestObject) (contract.ListChatModelsResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	limit, offset := 20, 0
	if q.Params.Limit != nil {
		limit = *q.Params.Limit
	}
	if q.Params.Offset != nil {
		offset = *q.Params.Offset
	}
	if limit < 1 || limit > 50 || offset < 0 {
		return chatFailure(m.ChatValidationError{}), nil
	}
	v, err := h.service.Models(ctx, a, limit, offset)
	if err != nil {
		return chatFailure(err), nil
	}
	result := contract.ListChatModels200JSONResponse{Items: []contract.ChatModel{}, NextOffset: v.NextOffset}
	for _, item := range v.Items {
		result.Items = append(result.Items, contract.ChatModel{Name: item.Name})
	}
	return result, nil
}
func (h *ChatHandler) CreateChatConversation(ctx context.Context, q contract.CreateChatConversationRequestObject) (contract.CreateChatConversationResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	if q.Body == nil || q.Body.RequestId == uuid.Nil {
		return chatFailure(m.ChatValidationError{}), nil
	}
	v, err := h.service.CreateConversation(ctx, a, q.Body.RequestId.String())
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.CreateChatConversation201JSONResponse(chatConversationMapper(v)), nil
}
func (h *ChatHandler) ListChatConversations(ctx context.Context, q contract.ListChatConversationsRequestObject) (contract.ListChatConversationsResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.Conversations(ctx, a, chatPageMapper(q.Params.Limit, q.Params.Cursor))
	if err != nil {
		return chatFailure(err), nil
	}
	result := contract.ListChatConversations200JSONResponse{Items: []contract.ChatConversation{}, NextCursor: chatStringMapper(v.NextCursor)}
	for _, item := range v.Items {
		result.Items = append(result.Items, chatConversationMapper(item))
	}
	return result, nil
}
func (h *ChatHandler) GetChatConversation(ctx context.Context, q contract.GetChatConversationRequestObject) (contract.GetChatConversationResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.Conversation(ctx, a, q.ConversationId.String())
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.GetChatConversation200JSONResponse(chatConversationMapper(v)), nil
}
func (h *ChatHandler) DeleteChatConversation(ctx context.Context, q contract.DeleteChatConversationRequestObject) (contract.DeleteChatConversationResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	if err := h.service.DeleteConversation(ctx, a, q.ConversationId.String()); err != nil {
		return chatFailure(err), nil
	}
	return contract.DeleteChatConversation204Response{}, nil
}
func (h *ChatHandler) ListChatMessages(ctx context.Context, q contract.ListChatMessagesRequestObject) (contract.ListChatMessagesResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.Messages(ctx, a, q.ConversationId.String(), chatPageMapper(q.Params.Limit, q.Params.Cursor))
	if err != nil {
		return chatFailure(err), nil
	}
	result := contract.ListChatMessages200JSONResponse{Items: []contract.ChatMessage{}, NextCursor: chatStringMapper(v.NextCursor)}
	for _, item := range v.Items {
		result.Items = append(result.Items, chatMessageMapper(item))
	}
	return result, nil
}
func (h *ChatHandler) SendChatMessage(ctx context.Context, q contract.SendChatMessageRequestObject) (contract.SendChatMessageResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	if q.Body == nil || q.Body.RequestId == uuid.Nil {
		return chatFailure(m.ChatValidationError{}), nil
	}
	v, err := h.service.Send(ctx, a, q.ConversationId.String(), m.ChatSendInput{RequestID: q.Body.RequestId.String(), Content: q.Body.Content})
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.SendChatMessage202JSONResponse{UserMessage: chatMessageMapper(v.UserMessage), AssistantMessage: chatMessageMapper(v.AssistantMessage)}, nil
}
func (h *ChatHandler) CancelChatTurn(ctx context.Context, q contract.CancelChatTurnRequestObject) (contract.CancelChatTurnResponseObject, error) {
	a, err := h.actor(ctx)
	if err != nil {
		return chatFailure(err), nil
	}
	v, err := h.service.Cancel(ctx, a, q.ConversationId.String(), q.TurnId.String())
	if err != nil {
		return chatFailure(err), nil
	}
	return contract.CancelChatTurn200JSONResponse(chatMessageMapper(v)), nil
}
