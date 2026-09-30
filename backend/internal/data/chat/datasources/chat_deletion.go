package datasources

import (
	"context"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
)

func chatScrubDeletedTx(ctx context.Context, tx pgx.Tx, conversation string, command m.ChatPrivacyCleanup) error {
	var deleted, closed bool
	if err := tx.QueryRow(ctx, "SELECT deleted_at IS NOT NULL,NOT EXISTS(SELECT 1 FROM chat_turns WHERE conversation_id=$1 AND NOT execution_closed) FROM chat_conversations WHERE id=$1", conversation).Scan(&deleted, &closed); err != nil {
		return err
	}
	if deleted != command.Deleted || closed != command.ExecutionsClosed {
		return nil
	}
	credentials := []string{}
	rows, err := tx.Query(ctx, "SELECT DISTINCT credential_id::text FROM chat_turns WHERE conversation_id=$1 AND credential_id IS NOT NULL", conversation)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		credentials = append(credentials, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, query := range []string{
		"DELETE FROM chat_sources WHERE turn_id IN(SELECT id FROM chat_turns WHERE conversation_id=$1)",
		"DELETE FROM chat_tool_results WHERE turn_id IN(SELECT id FROM chat_turns WHERE conversation_id=$1)",
		"UPDATE chat_messages SET content='' WHERE conversation_id=$1",
		"UPDATE chat_turns SET credential_id=NULL,base_url='',content_hash=''::bytea WHERE conversation_id=$1",
	} {
		if _, err := tx.Exec(ctx, query, conversation); err != nil {
			return err
		}
	}
	if _, err = tx.Exec(ctx, "UPDATE chat_conversations SET title=$2 WHERE id=$1", conversation, command.ReplacementTitle); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, "DELETE FROM chat_credentials c WHERE id=ANY($1::uuid[]) AND NOT EXISTS(SELECT 1 FROM chat_configuration WHERE credential_id=c.id) AND NOT EXISTS(SELECT 1 FROM chat_turns WHERE credential_id=c.id)", credentials)
	return err
}
