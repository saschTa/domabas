package datasources

import (
	"context"
	"encoding/base64"
	"encoding/json"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"time"
)

type ChatPageCursor struct {
	Account, Owner, Conversation, ID string
	Created                          time.Time
	Sequence                         int64
}

func chatCursorEncode(v ChatPageCursor) string {
	b, _ := json.Marshal(v)
	return base64.RawURLEncoding.EncodeToString(b)
}
func chatCursorDecode(v string, a m.ChatActor, conversation string) (ChatPageCursor, error) {
	var c ChatPageCursor
	if v == "" {
		return c, nil
	}
	body, err := base64.RawURLEncoding.DecodeString(v)
	if err != nil || len(body) > 1024 {
		return c, m.ChatValidationError{Message: "invalid chat cursor"}
	}
	if json.Unmarshal(body, &c) != nil || c.Account != a.AccountID || c.Owner != a.UserID || c.Conversation != conversation {
		return c, m.ChatValidationError{Message: "invalid chat cursor"}
	}
	return c, nil
}
func (s *ChatDataSource) CreateConversation(ctx context.Context, a m.ChatActor, requestID string) (m.ChatConversation, error) {
	if !m.ChatValidID(requestID) {
		return m.ChatConversation{}, m.ChatValidationError{Message: "invalid request ID"}
	}
	var c m.ChatConversation
	err := s.actorTx(ctx, a, false, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "INSERT INTO chat_conversations(id,account_id,owner_id,request_id) VALUES($1,$2,$3,$4) ON CONFLICT(account_id,owner_id,request_id) DO NOTHING", uuid.NewString(), a.AccountID, a.UserID, requestID); err != nil {
			return err
		}
		var id string
		err := tx.QueryRow(ctx, "SELECT id FROM chat_conversations WHERE account_id=$1 AND owner_id=$2 AND request_id=$3", a.AccountID, a.UserID, requestID).Scan(&id)
		if err != nil {
			return err
		}
		c, err = readChatConversation(ctx, tx, a, id)
		return err
	})
	return c, err
}
func (s *ChatDataSource) Conversation(ctx context.Context, a m.ChatActor, id string) (m.ChatConversation, error) {
	var c m.ChatConversation
	if !m.ChatValidID(id) {
		return c, m.ErrNotFound
	}
	err := s.readTx(ctx, a, false, func(tx pgx.Tx) error { var err error; c, err = readChatConversation(ctx, tx, a, id); return err })
	return c, err
}
func (s *ChatDataSource) Conversations(ctx context.Context, a m.ChatActor, p m.ChatPageRequest) (m.ChatConversationPage, error) {
	result := m.ChatConversationPage{Items: []m.ChatConversation{}}
	p, err := p.Normalize()
	if err != nil {
		return result, err
	}
	err = s.readTx(ctx, a, false, func(tx pgx.Tx) error {
		c, err := chatCursorDecode(p.Cursor, a, "")
		if err != nil {
			return err
		}
		if p.Cursor != "" && (!m.ChatValidID(c.ID) || c.Created.IsZero()) {
			return m.ChatValidationError{Message: "invalid conversation cursor"}
		}
		rows, err := tx.Query(ctx, `SELECT c.id,c.title,c.created_at,c.updated_at,COALESCE((SELECT t.id::text FROM chat_turns t WHERE t.conversation_id=c.id AND t.status IN ('queued','running')),'') FROM chat_conversations c WHERE account_id=$1 AND owner_id=$2 AND deleted_at IS NULL AND ($3='' OR (created_at,id)<($4,NULLIF($3,'')::uuid)) ORDER BY created_at DESC,id DESC LIMIT $5`, a.AccountID, a.UserID, c.ID, c.Created, p.Limit+1)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var v m.ChatConversation
			if err := rows.Scan(&v.ID, &v.Title, &v.CreatedAt, &v.UpdatedAt, &v.ActiveTurnID); err != nil {
				return err
			}
			result.Items = append(result.Items, v)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		if len(result.Items) > p.Limit {
			result.Items = result.Items[:p.Limit]
			last := result.Items[p.Limit-1]
			result.NextCursor = chatCursorEncode(ChatPageCursor{Account: a.AccountID, Owner: a.UserID, ID: last.ID, Created: last.CreatedAt})
		}
		return nil
	})
	return result, err
}
func (s *ChatDataSource) DeleteConversation(ctx context.Context, a m.ChatActor, id string, command m.ChatCancellationCommand) error {
	if !m.ChatValidID(id) {
		return m.ErrNotFound
	}
	return s.actorTx(ctx, a, false, func(tx pgx.Tx) error {
		if _, err := lockChatConversation(ctx, tx, a, id); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "UPDATE chat_conversations SET deleted_at=clock_timestamp() WHERE id=$1", id); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, "UPDATE chat_turns SET status=$3,stage=$4,updated_at=clock_timestamp(),finished_at=clock_timestamp(),execution_closed=admitted_at IS NULL WHERE conversation_id=$1 AND status=ANY($2::text[])", id, command.ExpectedStates, command.Status, command.Stage)
		if err != nil {
			return err
		}
		return chatScrubDeletedTx(ctx, tx, id, command.Cleanup)
	})
}
func (s *ChatDataSource) Cancel(ctx context.Context, a m.ChatActor, conversation, id string, command m.ChatCancellationCommand) (m.ChatMessage, error) {
	var result m.ChatMessage
	if !m.ChatValidID(conversation) || !m.ChatValidID(id) {
		return result, m.ErrNotFound
	}
	err := s.actorTx(ctx, a, false, func(tx pgx.Tx) error {
		if _, err := lockChatConversation(ctx, tx, a, conversation); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "UPDATE chat_turns SET status=$4,stage=$5,updated_at=clock_timestamp(),finished_at=clock_timestamp(),execution_closed=admitted_at IS NULL WHERE id=$1 AND conversation_id=$2 AND status=ANY($3::text[])", id, conversation, command.ExpectedStates, command.Status, command.Stage); err != nil {
			return err
		}
		var err error
		result, err = chatMessageTx(ctx, tx, conversation, id, "assistant")
		return err
	})
	return result, err
}
