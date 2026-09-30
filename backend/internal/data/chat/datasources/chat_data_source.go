package datasources

import (
	"context"
	"crypto/cipher"
	"errors"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
)

type ChatResourceScheduler interface {
	Reserve(context.Context, pgx.Tx, string, string, []string) (bool, error)
}

type ChatDataSource struct {
	scheduler ChatResourceScheduler
	db        *postgres.PostgresDatabase
	vault     cipher.AEAD
	queue     string
}

func NewChatDataSource(ctx context.Context, db *postgres.PostgresDatabase, keyPath, queue string, scheduler ChatResourceScheduler) (*ChatDataSource, error) {
	key, err := CredentialKey(ctx, db, "", keyPath)
	if err != nil {
		return nil, err
	}
	vault, err := credentialCipher(key)
	if err != nil {
		return nil, err
	}
	return &ChatDataSource{db: db, vault: vault, queue: queue, scheduler: scheduler}, nil
}
func chatUnavailable(err, errorValue error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return errorValue
	}
	return err
}

func (s *ChatDataSource) actorTx(ctx context.Context, a m.ChatActor, admin bool, fn func(pgx.Tx) error) error {
	return s.scopedTx(ctx, a, admin, pgx.TxOptions{}, fn)
}
func (s *ChatDataSource) readTx(ctx context.Context, a m.ChatActor, admin bool, fn func(pgx.Tx) error) error {
	return s.scopedTx(ctx, a, admin, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, fn)
}
func (s *ChatDataSource) scopedTx(ctx context.Context, a m.ChatActor, admin bool, options pgx.TxOptions, fn func(pgx.Tx) error) error {
	return pgx.BeginTxFunc(ctx, s.db, options, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		return fn(tx)
	})
}
func lockChatConversation(ctx context.Context, tx pgx.Tx, a m.ChatActor, id string) (m.ChatConversation, error) {
	return queryChatConversation(ctx, tx, a, id, " FOR UPDATE")
}
func readChatConversation(ctx context.Context, tx pgx.Tx, a m.ChatActor, id string) (m.ChatConversation, error) {
	return queryChatConversation(ctx, tx, a, id, "")
}
func queryChatConversation(ctx context.Context, tx pgx.Tx, a m.ChatActor, id, lock string) (m.ChatConversation, error) {
	var c m.ChatConversation
	err := tx.QueryRow(ctx, `SELECT c.id,c.title,c.created_at,c.updated_at,COALESCE((SELECT t.id::text FROM chat_turns t WHERE t.conversation_id=c.id AND t.status IN ('queued','running')),'') FROM chat_conversations c WHERE c.id=$1 AND c.account_id=$2 AND c.owner_id=$3 AND c.deleted_at IS NULL`+lock, id, a.AccountID, a.UserID).Scan(&c.ID, &c.Title, &c.CreatedAt, &c.UpdatedAt, &c.ActiveTurnID)
	return c, chatUnavailable(err, m.ErrNotFound)
}
