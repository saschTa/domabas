package datasources

import (
	"context"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/jackc/pgx/v5"
)

func (s *InvoiceDataSource) SaveClassification(ctx context.Context, work m.InvoiceWork, result m.InvoiceClassification) error {
	if result.Validate() != nil || work.Job.AIAttempt < 1 || work.ClassifierVersion != m.InvoiceClassifierVersion || result.Pass != work.Classification.Pass+1 {
		return document.DocumentProcessingError{Code: "invalid_classification"}
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		job := work.Job
		if err := activeAI(ctx, tx, job); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE document_ai_jobs SET invoice_decision=$5,invoice_decision_reason=$6,invoice_classification_pass=$7,invoice_input_characters=$8,invoice_source_characters=$9,updated_at=clock_timestamp()
WHERE account_id=$1 AND document_id=$2 AND attempt=$3 AND ocr_revision=$4 AND invoice_classifier_version=$10 AND invoice_classification_pass=$11 AND NOT invoice_done AND stage='invoicing'`,
			job.AccountID, job.DocumentID, job.AIAttempt, work.Revision, result.Decision, result.Reason, result.Pass, result.InputCharacters, result.SourceCharacters, work.ClassifierVersion, work.Classification.Pass)
		if err == nil && tag.RowsAffected() != 1 {
			return document.ErrStaleJob
		}
		return err
	})
}
