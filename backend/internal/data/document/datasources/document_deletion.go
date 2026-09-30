package datasources

import (
	"context"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) Delete(ctx context.Context, a m.DocumentActor, id string) error {
	return s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		if err := lockDocument(ctx, tx, a.AccountID, id); err != nil {
			return err
		}
		var processingID string
		if err := tx.QueryRow(ctx, "SELECT document_id FROM document_processing WHERE account_id=$1 AND document_id=$2 FOR UPDATE", a.AccountID, id).Scan(&processingID); err != nil && err != pgx.ErrNoRows {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO document_cleanup(document_id,account_id,uploader_id) SELECT document_id,account_id,uploader_id FROM document_files WHERE account_id=$1 AND document_id=$2 ON CONFLICT(document_id) DO NOTHING`, a.AccountID, id); err != nil {
			return err
		}
		for _, query := range []string{
			"DELETE FROM document_outbox WHERE account_id=$1 AND document_id=$2",
			"DELETE FROM document_chunks WHERE account_id=$1 AND document_id=$2",
			"DELETE FROM document_processing WHERE account_id=$1 AND document_id=$2",
			"DELETE FROM document_files WHERE account_id=$1 AND document_id=$2",
			"DELETE FROM document_uploads WHERE account_id=$1 AND id=$2",
			"DELETE FROM documents WHERE account_id=$1 AND id=$2",
		} {
			if _, err := tx.Exec(ctx, query, a.AccountID, id); err != nil {
				return err
			}
		}
		return nil
	})
}
func (s *DocumentDataSource) ReapDeletedRecords(ctx context.Context, limit int) ([]r.DocumentCleanupRecord, error) {
	if limit < 1 || limit > 20 {
		limit = 20
	}
	result := []r.DocumentCleanupRecord{}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `WITH candidates AS(SELECT document_id FROM document_cleanup WHERE next_attempt_at<=clock_timestamp() AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) ORDER BY next_attempt_at,document_id LIMIT $1 FOR UPDATE SKIP LOCKED) UPDATE document_cleanup c SET lease_token=gen_random_uuid(),lease_expires_at=clock_timestamp()+interval '30 seconds' FROM candidates d WHERE c.document_id=d.document_id RETURNING c.account_id,c.uploader_id,c.document_id,c.lease_token,c.attempts`, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var item r.DocumentCleanupRecord
			if err := rows.Scan(&item.AccountID, &item.UploaderID, &item.DocumentID, &item.LeaseToken, &item.Attempts); err != nil {
				return err
			}
			result = append(result, item)
		}
		return rows.Err()
	})
	return result, err
}
func (s *DocumentDataSource) DeletedReaped(ctx context.Context, lease m.DocumentCleanupLease, command m.DocumentCleanupCompletion) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE document_cleanup SET lease_token=NULL,lease_expires_at=NULL,attempts=$5,next_attempt_at=$6 WHERE account_id=$1 AND uploader_id=$2 AND document_id=$3 AND lease_token=$4 AND lease_expires_at>clock_timestamp() AND attempts=$7`, lease.AccountID, lease.UploaderID, lease.DocumentID, lease.LeaseToken, command.Attempts, command.NextAttempt, lease.Attempts)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		return err
	})
}
