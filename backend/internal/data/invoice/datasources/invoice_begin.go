package datasources

import (
	"context"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/jackc/pgx/v5"
)

func (s *InvoiceDataSource) BeginWork(ctx context.Context, w m.InvoiceWork) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		job := w.Job
		if job.AIAttempt > 0 {
			if err := activeAI(ctx, tx, job); err != nil {
				return err
			}
			tag, err := tx.Exec(ctx, `UPDATE document_ai_jobs SET status='running',stage='invoicing',started_at=COALESCE(started_at,clock_timestamp()),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND attempt=$3 AND ocr_revision=$4 AND stage=$5 AND NOT invoice_done`, job.AccountID, job.DocumentID, job.AIAttempt, w.Revision, w.Stage)
			if err == nil && tag.RowsAffected() != 1 {
				return d.ErrStaleJob
			}
			return err
		}
		if err := active(ctx, tx, job); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE document_processing SET invoice_next_stage=$6,stage='invoicing',updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND ocr_revision=$4 AND stage=$5 AND invoice_completed_generation IS DISTINCT FROM generation`, job.AccountID, job.DocumentID, job.Generation, w.Revision, w.Stage, w.ResumeStage)
		if err == nil && tag.RowsAffected() != 1 {
			return d.ErrStaleJob
		}
		return err
	})
}
