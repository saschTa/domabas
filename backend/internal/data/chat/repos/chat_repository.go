package repos

import p "github.com/domabas/domabas/backend/internal/domain/chat/interfaces"

type ChatSource interface {
	p.ChatRepository
	p.ChatExecutionRepository
}
type ChatRepository struct{ ChatSource }

func NewChatRepository(source ChatSource) *ChatRepository { return &ChatRepository{source} }
