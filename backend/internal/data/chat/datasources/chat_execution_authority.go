package datasources

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
)

func (s *ChatDataSource) ExecutionAuthority(ctx context.Context, id string, query m.ChatContextQuery) (m.ChatExecutionAuthority, error) {
	var result m.ChatExecutionAuthority
	err := pgx.BeginTxFunc(ctx, s.db, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		var conversation string
		err := tx.QueryRow(ctx, `SELECT account_id,owner_id,credential_revision,conversation_id FROM chat_turns WHERE id=$1`, id).Scan(&result.Actor.AccountID, &result.Actor.UserID, &result.Actor.CredentialRevision, &conversation)
		if err != nil {
			return chatUnavailable(err, m.ErrNotFound)
		}
		return tx.QueryRow(ctx, `WITH history AS (SELECT m.turn_id,m.role FROM chat_messages m JOIN chat_turns t ON t.id=m.turn_id WHERE m.conversation_id=$1 AND m.sequence<=(SELECT sequence FROM chat_messages WHERE turn_id=$2 AND role='user') AND (m.role='user' OR t.status=$4) ORDER BY sequence DESC LIMIT $3), evidence AS (SELECT s.document_id,t.account_id FROM chat_sources s JOIN chat_turns t ON t.id=s.turn_id WHERE t.id=$2 OR t.id IN(SELECT turn_id FROM history WHERE role='assistant')) SELECT EXISTS(SELECT 1 FROM evidence),EXISTS(SELECT 1 FROM evidence e LEFT JOIN documents d ON d.id=e.document_id AND d.account_id=e.account_id WHERE d.id IS NULL)`, conversation, id, query.MessageLimit, query.AssistantStatus).Scan(&result.EvidencePresent, &result.EvidenceMissing)
	})
	return result, err
}
