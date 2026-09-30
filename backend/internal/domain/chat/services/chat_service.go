package services

import (
	"context"
	"errors"
	p "github.com/domabas/domabas/backend/internal/domain/chat/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
)

type ChatService struct {
	repository   p.ChatRepository
	provider     p.ChatProvider
	modelContext p.ChatModelContextProvider
	authority    p.ChatAuthority
}

func NewChatService(repository p.ChatRepository, provider p.ChatProvider, modelContext p.ChatModelContextProvider, authority p.ChatAuthority) *ChatService {
	return &ChatService{repository: repository, provider: provider, modelContext: modelContext, authority: authority}
}
func chatAuthorityError(err error) error {
	if errors.Is(err, i.ErrUnauthorized) {
		return m.ErrUnauthorized
	}
	if errors.Is(err, i.ErrForbidden) || errors.Is(err, i.ErrPasswordChange) {
		return m.ErrForbidden
	}
	return err
}
func (s *ChatService) authorize(ctx context.Context, a m.ChatActor, admin bool) error {
	if s.authority == nil {
		return m.ErrForbidden
	}
	principal, err := s.authority.ResolveAuthority(ctx, i.IdentityPrincipal{AccountID: a.AccountID, UserID: a.UserID, SessionDigest: a.SessionDigest, CredentialRevision: a.CredentialRevision})
	if err != nil {
		return chatAuthorityError(err)
	}
	claim := i.IdentityPermission("chat:use")
	if admin {
		claim = i.IdentityPermission("system:chat:manage")
	}
	if !principal.HasPermission(claim) {
		return m.ErrForbidden
	}
	return nil
}
func (s *ChatService) Configuration(ctx context.Context, a m.ChatActor, admin bool) (m.ChatConfiguration, error) {
	if err := s.authorize(ctx, a, admin); err != nil {
		return m.ChatConfiguration{}, err
	}
	c, err := s.repository.Configuration(ctx, a, admin)
	if !admin {
		c.BaseURL, c.CredentialID, c.HasAPIKey = "", "", false
	}
	return c, err
}
func (s *ChatService) UpdateConfiguration(ctx context.Context, a m.ChatActor, input m.ChatConfigurationUpdate) (m.ChatConfiguration, error) {
	if err := s.authorize(ctx, a, true); err != nil {
		return m.ChatConfiguration{}, err
	}
	input, err := input.Normalize()
	if err != nil {
		return m.ChatConfiguration{}, err
	}
	current, err := s.repository.Configuration(ctx, a, true)
	if err != nil {
		return m.ChatConfiguration{}, err
	}
	if s.provider == nil {
		return m.ChatConfiguration{}, m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	internal := s.provider.UsesInternalRuntime(m.ChatConfiguration{Provider: input.Provider, BaseURL: input.BaseURL})
	plan, err := m.PlanChatConfiguration(current, input, internal)
	if err != nil {
		return m.ChatConfiguration{}, err
	}
	return s.repository.UpdateConfiguration(ctx, a, plan)
}
func (s *ChatService) Conversations(ctx context.Context, a m.ChatActor, page m.ChatPageRequest) (m.ChatConversationPage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.ChatConversationPage{}, err
	}
	return s.repository.Conversations(ctx, a, page)
}
func (s *ChatService) CreateConversation(ctx context.Context, a m.ChatActor, requestID string) (m.ChatConversation, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.ChatConversation{}, err
	}
	return s.repository.CreateConversation(ctx, a, requestID)
}
func (s *ChatService) Conversation(ctx context.Context, a m.ChatActor, id string) (m.ChatConversation, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.ChatConversation{}, err
	}
	return s.repository.Conversation(ctx, a, id)
}
func (s *ChatService) DeleteConversation(ctx context.Context, a m.ChatActor, id string) error {
	if err := s.authorize(ctx, a, false); err != nil {
		return err
	}
	return s.repository.DeleteConversation(ctx, a, id, m.ChatCancellation())
}
func (s *ChatService) Messages(ctx context.Context, a m.ChatActor, id string, page m.ChatPageRequest) (m.ChatMessagePage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.ChatMessagePage{}, err
	}
	return s.repository.Messages(ctx, a, id, page)
}
func (s *ChatService) Send(ctx context.Context, a m.ChatActor, id string, input m.ChatSendInput) (m.ChatSendResult, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.ChatSendResult{}, err
	}
	if err := input.Validate(); err != nil {
		return m.ChatSendResult{}, err
	}
	facts, err := s.repository.SendFacts(ctx, a, id, input)
	if err != nil {
		return m.ChatSendResult{}, err
	}
	if facts.Replay != nil {
		return *facts.Replay, nil
	}
	command, err := m.PlanChatSend(facts, input)
	if err != nil {
		return m.ChatSendResult{}, err
	}
	return s.repository.Send(ctx, a, id, command)
}
func (s *ChatService) Cancel(ctx context.Context, a m.ChatActor, conversation, turn string) (m.ChatMessage, error) {
	if err := s.authorize(ctx, a, false); err != nil {
		return m.ChatMessage{}, err
	}
	return s.repository.Cancel(ctx, a, conversation, turn, m.ChatCancellation())
}
func (s *ChatService) Models(ctx context.Context, actor m.ChatActor, limit, offset int) (m.ChatModelPage, error) {
	if limit < 1 || limit > 50 || offset < 0 {
		return m.ChatModelPage{}, m.ChatValidationError{Message: "invalid model page"}
	}
	if _, err := s.Configuration(ctx, actor, true); err != nil {
		return m.ChatModelPage{}, err
	}
	return s.provider.Models(ctx, limit, offset)
}
func (s *ChatService) ModelContext(ctx context.Context, actor m.ChatActor, model string) (m.ChatModelContext, error) {
	if !m.ChatValidModel(model) {
		return m.ChatModelContext{}, m.ChatValidationError{Message: "invalid chat model"}
	}
	if _, err := s.Configuration(ctx, actor, true); err != nil {
		return m.ChatModelContext{}, err
	}
	return s.modelContext.ModelContext(ctx, model)
}
