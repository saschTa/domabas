package datasources

import (
	"context"
	"crypto/sha256"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"slices"
)

const chatMessageColumns = `m.id,m.conversation_id,m.turn_id,m.sequence,m.role,m.content,m.created_at,GREATEST(m.updated_at,t.updated_at),CASE WHEN m.role='user' THEN 'completed' ELSE t.status END,CASE WHEN m.role='user' THEN 'completed' ELSE t.stage END,CASE WHEN m.role='user' THEN '' ELSE t.failure_code END,t.provider,t.model`

type ChatRowScanner interface{ Scan(...any) error }

func chatSourcesTx(ctx context.Context, tx pgx.Tx, v *m.ChatMessage) error {
	if v.Role != "assistant" {
		return nil
	}
	rows, err := tx.Query(ctx, "SELECT DISTINCT ON (document_id) document_id,title,excerpt FROM chat_sources WHERE turn_id=$1 ORDER BY document_id,ordinal", v.TurnID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var s m.ChatSource
		if err := rows.Scan(&s.DocumentID, &s.Title, &s.Excerpt); err != nil {
			return err
		}
		v.Sources = append(v.Sources, s)
	}
	return rows.Err()
}
func chatMessageTx(ctx context.Context, tx pgx.Tx, conversation, turn, role string) (m.ChatMessage, error) {
	v, err := chatMessageMapper(tx.QueryRow(ctx, "SELECT "+chatMessageColumns+" FROM chat_messages m JOIN chat_turns t ON t.id=m.turn_id WHERE m.conversation_id=$1 AND m.turn_id=$2 AND m.role=$3", conversation, turn, role))
	if err != nil {
		return v, chatUnavailable(err, m.ErrNotFound)
	}
	return v, chatSourcesTx(ctx, tx, &v)
}
func (s *ChatDataSource) Messages(ctx context.Context, a m.ChatActor, id string, p m.ChatPageRequest) (m.ChatMessagePage, error) {
	result := m.ChatMessagePage{Items: []m.ChatMessage{}}
	p, err := p.Normalize()
	if err != nil {
		return result, err
	}
	if !m.ChatValidID(id) {
		return result, m.ErrNotFound
	}
	err = s.readTx(ctx, a, false, func(tx pgx.Tx) error {
		if _, err := readChatConversation(ctx, tx, a, id); err != nil {
			return err
		}
		c, err := chatCursorDecode(p.Cursor, a, id)
		if err != nil {
			return err
		}
		if p.Cursor != "" && c.Sequence < 1 {
			return m.ChatValidationError{Message: "invalid message cursor"}
		}
		rows, err := tx.Query(ctx, "SELECT "+chatMessageColumns+" FROM chat_messages m JOIN chat_turns t ON t.id=m.turn_id WHERE m.conversation_id=$1 AND ($2::bigint=0 OR sequence<$2) ORDER BY sequence DESC LIMIT $3", id, c.Sequence, p.Limit+1)
		if err != nil {
			return err
		}
		for rows.Next() {
			v, err := chatMessageMapper(rows)
			if err != nil {
				rows.Close()
				return err
			}
			result.Items = append(result.Items, v)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if len(result.Items) > p.Limit {
			result.Items = result.Items[:p.Limit]
			result.NextCursor = chatCursorEncode(ChatPageCursor{Account: a.AccountID, Owner: a.UserID, Conversation: id, Sequence: result.Items[p.Limit-1].Sequence})
		}
		for i := range result.Items {
			if err := chatSourcesTx(ctx, tx, &result.Items[i]); err != nil {
				return err
			}
		}
		return nil
	})
	return result, err
}
func (s *ChatDataSource) Send(ctx context.Context, a m.ChatActor, id string, command m.ChatSendCommand) (m.ChatSendResult, error) {
	input := command.Input
	var result m.ChatSendResult
	if err := input.Validate(); err != nil {
		return result, err
	}
	if !m.ChatValidID(id) {
		return result, m.ErrNotFound
	}
	hash := sha256.Sum256([]byte(input.Content))
	err := s.actorTx(ctx, a, false, func(tx pgx.Tx) error {
		conversation, err := lockChatConversation(ctx, tx, a, id)
		if err != nil {
			return err
		}
		var turn string
		var previous []byte
		err = tx.QueryRow(ctx, "SELECT id,content_hash FROM chat_turns WHERE conversation_id=$1 AND request_id=$2", id, input.RequestID).Scan(&turn, &previous)
		if err == nil {
			if !slices.Equal(previous, hash[:]) {
				return m.ErrConflict
			}
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return err
		} else {
			if err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT id::text FROM chat_turns WHERE conversation_id=$1 AND status IN ('queued','running')),'')`, id).Scan(&conversation.ActiveTurnID); err != nil {
				return err
			}
			if conversation.ActiveTurnID != "" {
				return m.ErrConflict
			}
			configuration, err := shareChatConfiguration(ctx, tx)
			if err != nil {
				return err
			}
			if configuration.Revision != command.ExpectedConfigurationRevision {
				return m.ErrConflict
			}
			var singleton bool
			if err := tx.QueryRow(ctx, "SELECT singleton FROM chat_admission WHERE singleton FOR UPDATE").Scan(&singleton); err != nil {
				return err
			}
			var count int
			if err := tx.QueryRow(ctx, "SELECT count(*) FROM chat_turns WHERE status IN ('queued','running')").Scan(&count); err != nil {
				return err
			}
			if count >= command.GlobalLimit {
				return m.ErrBusy
			}
			if err := tx.QueryRow(ctx, "SELECT count(*) FROM chat_turns WHERE owner_id=$1 AND status IN ('queued','running')", a.UserID).Scan(&count); err != nil {
				return err
			}
			if count >= command.OwnerLimit {
				return m.ErrBusy
			}
			turn = uuid.NewString()
			_, err = tx.Exec(ctx, `INSERT INTO chat_turns(id,conversation_id,account_id,owner_id,request_id,credential_revision,content_hash,configuration_revision,provider,model,base_url,credential_id,internal_runtime,workflow_id,task_queue,context_length,thinking_enabled) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,NULLIF($12,'')::uuid,$13,$14,$15,$16,$17)`, turn, id, a.AccountID, a.UserID, input.RequestID, a.CredentialRevision, hash[:], configuration.Revision, configuration.Provider, configuration.Model, configuration.BaseURL, configuration.CredentialID, configuration.InternalRuntime, "domabas-chat-"+turn, s.queue, configuration.ContextLength, configuration.ThinkingEnabled)
			if err != nil {
				return err
			}
			var sequence int64
			if err := tx.QueryRow(ctx, "UPDATE chat_conversations SET next_sequence=next_sequence+2,updated_at=clock_timestamp() WHERE id=$1 RETURNING next_sequence-2", id).Scan(&sequence); err != nil {
				return err
			}
			_, err = tx.Exec(ctx, "INSERT INTO chat_messages(id,conversation_id,turn_id,sequence,role,content) VALUES($1,$2,$3,$4,'user',$5),($6,$2,$3,$7,'assistant','')", uuid.NewString(), id, turn, sequence, input.Content, uuid.NewString(), sequence+1)
			if err != nil {
				return err
			}
			if sequence == 1 {
				if _, err := tx.Exec(ctx, "UPDATE chat_conversations SET title=$2 WHERE id=$1", id, command.InitialTitle); err != nil {
					return err
				}
			}
		}
		result.UserMessage, err = chatMessageTx(ctx, tx, id, turn, "user")
		if err != nil {
			return err
		}
		result.AssistantMessage, err = chatMessageTx(ctx, tx, id, turn, "assistant")
		return err
	})
	return result, err
}
