package handlers

import (
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func chatStringMapper(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}
func chatConversationMapper(v m.ChatConversation) contract.ChatConversation {
	r := contract.ChatConversation{Id: uuid.MustParse(v.ID), Title: v.Title, CreatedAt: v.CreatedAt, UpdatedAt: v.UpdatedAt}
	if v.ActiveTurnID != "" {
		id := uuid.MustParse(v.ActiveTurnID)
		r.ActiveTurnId = &id
	}
	return r
}
func chatMessageMapper(v m.ChatMessage) contract.ChatMessage {
	r := contract.ChatMessage{Id: uuid.MustParse(v.ID), ConversationId: uuid.MustParse(v.ConversationID), TurnId: uuid.MustParse(v.TurnID), Sequence: v.Sequence, Role: contract.ChatMessageRole(v.Role), Content: v.Content, Status: contract.ChatMessageStatus(v.Status), Stage: contract.ChatMessageStage(v.Stage), FailureCode: chatStringMapper(v.FailureCode), Provider: contract.ChatMessageProvider(v.Provider), Model: v.Model, CreatedAt: v.CreatedAt, UpdatedAt: v.UpdatedAt, Sources: []contract.ChatSource{}}
	for _, s := range v.Sources {
		r.Sources = append(r.Sources, contract.ChatSource{DocumentId: uuid.MustParse(s.DocumentID), Title: s.Title, Excerpt: s.Excerpt})
	}
	return r
}
func chatConfigurationMapper(v m.ChatConfiguration) contract.ChatConfiguration {
	return contract.ChatConfiguration{ThinkingEnabled: new(v.ThinkingEnabled), Enabled: v.Enabled, Provider: contract.ChatConfigurationProvider(v.Provider), Model: v.Model, Revision: v.Revision, BaseUrl: v.BaseURL, HasApiKey: v.HasAPIKey, ContextLength: v.ContextLength}
}
func chatPageMapper(limit *int, cursor *string) m.ChatPageRequest {
	r := m.ChatPageRequest{Limit: 20}
	if limit != nil {
		r.Limit = *limit
	}
	if cursor != nil {
		r.Cursor = *cursor
	}
	return r
}
