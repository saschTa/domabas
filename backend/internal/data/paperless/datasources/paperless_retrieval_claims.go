package datasources

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (s *PaperlessJobsDataSource) claimRetrievals(ctx context.Context, tx pgx.Tx, id string, limit int, policy m.PaperlessRetrievalPolicy, w *m.PaperlessWork) error {
	if _, err := tx.Exec(ctx, `UPDATE paperless_items SET claim_token=NULL,claim_deadline=NULL,claim_recover_after=NULL
WHERE claim_token IS NOT NULL AND claim_recover_after<=clock_timestamp()`); err != nil {
		return err
	}
	var active int
	if err := tx.QueryRow(ctx, "SELECT count(*) FROM paperless_items WHERE claim_token IS NOT NULL").Scan(&active); err != nil {
		return err
	}
	if err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM paperless_items WHERE run_id=$1 AND status='pending')", id).Scan(&w.Waiting); err != nil {
		return err
	}
	if active >= limit || !w.Waiting {
		return nil
	}
	rows, err := tx.Query(ctx, `WITH pending AS (
SELECT source_id FROM paperless_items WHERE run_id=$1 AND status='pending' AND claim_token IS NULL ORDER BY source_id LIMIT $2 FOR UPDATE)
UPDATE paperless_items i SET claim_token=$3,claim_deadline=clock_timestamp()+$4::interval,claim_recover_after=clock_timestamp()+$5::interval
FROM pending p WHERE i.run_id=$1 AND i.source_id=p.source_id RETURNING i.source_id,i.title,i.claim_token,i.claim_deadline`, id, limit-active, uuid.NewString(), policy.OperationTimeout.String(), policy.RecoveryTimeout.String())
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var item m.PaperlessRetrieval
		if err := rows.Scan(&item.Document.ID, &item.Document.Title, &item.ClaimToken, &item.Deadline); err != nil {
			return err
		}
		w.Items = append(w.Items, item)
	}
	return rows.Err()
}

func (s *PaperlessJobsDataSource) ReleaseClaims(ctx context.Context, id string, items []m.PaperlessRetrieval) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		for _, item := range items {
			if _, err := tx.Exec(ctx, "UPDATE paperless_items SET claim_token=NULL,claim_deadline=NULL,claim_recover_after=NULL WHERE run_id=$1 AND source_id=$2 AND claim_token=$3", id, item.Document.ID, item.ClaimToken); err != nil {
				return err
			}
		}
		return nil
	})
}

func (s *PaperlessJobsDataSource) RunActive(ctx context.Context, id string) (bool, error) {
	var active bool
	err := s.db.QueryRow(ctx, "SELECT state='running' AND NOT cancel_requested FROM paperless_runs WHERE id=$1", id).Scan(&active)
	return active, err
}
