package datasources

import (
	"context"
	"crypto/sha256"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
	"slices"
)

func (s *ChatDataSource) SendFacts(ctx context.Context, a m.ChatActor, id string, input m.ChatSendInput) (m.ChatSendFacts, error) {
	var result m.ChatSendFacts
	if !m.ChatValidID(id) {
		return result, m.ErrNotFound
	}
	err := s.readTx(ctx, a, false, func(tx pgx.Tx) error {
		var err error
		result.Conversation, err = readChatConversation(ctx, tx, a, id)
		if err != nil {
			return err
		}
		var turn string
		var previous []byte
		err = tx.QueryRow(ctx, "SELECT id,content_hash FROM chat_turns WHERE conversation_id=$1 AND request_id=$2", id, input.RequestID).Scan(&turn, &previous)
		if err == nil {
			hash := sha256.Sum256([]byte(input.Content))
			if !slices.Equal(previous, hash[:]) {
				return m.ErrConflict
			}
			result.Replay = &m.ChatSendResult{}
			result.Replay.UserMessage, err = chatMessageTx(ctx, tx, id, turn, "user")
			if err != nil {
				return err
			}
			result.Replay.AssistantMessage, err = chatMessageTx(ctx, tx, id, turn, "assistant")
			return err
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		result.Configuration, err = readChatConfiguration(ctx, tx)
		return err
	})
	return result, err
}
