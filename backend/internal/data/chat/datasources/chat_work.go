package datasources

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
	"slices"
)

func (s *ChatDataSource) Work(ctx context.Context, id, token string, query m.ChatContextQuery) (m.ChatWork, error) {
	w := m.ChatWork{ID: id, ExecutionToken: token, Messages: []m.ChatMessage{}, Tools: []m.ChatToolResult{}}
	err := s.executionTx(ctx, id, token, func(tx pgx.Tx, a m.ChatActor, conversation string) error {
		w.Actor = a
		w.ConversationID = conversation
		if err := s.evidenceExists(ctx, tx, conversation, id, query); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `SELECT configuration_revision,provider,model,base_url,COALESCE(credential_id::text,''),internal_runtime,context_length,thinking_enabled FROM chat_turns WHERE id=$1`, id).Scan(&w.Configuration.Revision, &w.Configuration.Provider, &w.Configuration.Model, &w.Configuration.BaseURL, &w.Configuration.CredentialID, &w.Configuration.InternalRuntime, &w.Configuration.ContextLength, &w.Configuration.ThinkingEnabled); err != nil {
			return err
		}
		var err error
		w.APIKey, err = s.credential(ctx, tx, w.Configuration.CredentialID)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, "SELECT "+chatMessageColumns+` FROM chat_messages m JOIN chat_turns t ON t.id=m.turn_id WHERE m.conversation_id=$1 AND m.sequence<=(SELECT sequence FROM chat_messages WHERE turn_id=$2 AND role='user') AND (m.role='user' OR t.status=$4) ORDER BY sequence DESC LIMIT $3`, conversation, id, query.MessageLimit, query.AssistantStatus)
		if err != nil {
			return err
		}
		for rows.Next() {
			v, err := chatMessageMapper(rows)
			if err != nil {
				rows.Close()
				return err
			}
			w.Messages = append(w.Messages, v)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		slices.Reverse(w.Messages)
		w.Tools, err = chatToolResults(ctx, tx, id)
		return err
	})
	return w, err
}
