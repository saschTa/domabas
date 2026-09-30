package datasources

import (
	"context"
	"encoding/json"
	"errors"

	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/jackc/pgx/v5"
)

type InvoiceDataSource struct{ database *postgres.PostgresDatabase }

func NewInvoiceDataSource(database *postgres.PostgresDatabase) *InvoiceDataSource {
	return &InvoiceDataSource{database: database}
}
func (s *InvoiceDataSource) readTx(ctx context.Context, a document.DocumentActor, fn func(pgx.Tx) error) error {
	return pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, fn)
}
func active(ctx context.Context, tx pgx.Tx, j document.DocumentJob) error {
	var id string
	if err := tx.QueryRow(ctx, "SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE", j.AccountID, j.DocumentID).Scan(&id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return document.ErrStaleJob
		}
		return err
	}
	err := tx.QueryRow(ctx, `SELECT document_id FROM document_processing WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND ocr_revision=(SELECT ocr_revision FROM documents WHERE account_id=$1 AND id=$2) AND state IN ('queued','processing') AND ((processing_deadline IS NULL AND (delivery_deadline>clock_timestamp() OR (unlimited_inference AND processing_started_at IS NOT NULL))) OR processing_deadline>clock_timestamp()) FOR UPDATE`, j.AccountID, j.DocumentID, j.Generation).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return document.ErrStaleJob
	}
	return err
}
func (s *InvoiceDataSource) Work(ctx context.Context, j document.DocumentJob) (m.InvoiceWork, error) {
	if j.AIAttempt > 0 {
		return s.aiWork(ctx, j)
	}
	result := m.InvoiceWork{Job: j}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := active(ctx, tx, j); err != nil {
			return err
		}
		var config []byte
		err := tx.QueryRow(ctx, `SELECT p.ocr_revision,p.invoice_completed_generation IS NOT DISTINCT FROM p.generation,p.invoice_xml,p.configuration,p.stage,COALESCE(p.invoice_next_stage,''),f.media_type,COALESCE(d.ocr_manual_text,d.ocr_machine_text,'') FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id JOIN document_files f ON f.account_id=p.account_id AND f.document_id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2`, j.AccountID, j.DocumentID).Scan(&result.Revision, &result.Done, &result.XML, &config, &result.Stage, &result.ResumeStage, &result.MediaType, &result.Text)
		if err != nil {
			return err
		}
		var configuration document.DocumentProcessingConfiguration
		if err = json.Unmarshal(config, &configuration); err != nil {
			return err
		}
		result.Configuration = configuration.LLM
		if result.Done {
			return nil
		}
		if err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT source FROM invoices WHERE account_id=$1 AND document_id=$2),'')`, j.AccountID, j.DocumentID).Scan(&result.ExistingSource); err != nil {
			return err
		}
		return err
	})
	return result, err
}
func (s *InvoiceDataSource) Save(ctx context.Context, w m.InvoiceWork, v *r.InvoiceRecord) error {
	if w.Job.AIAttempt > 0 {
		return s.aiSave(ctx, w, v)
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		j := w.Job
		if err := active(ctx, tx, j); err != nil {
			return err
		}
		var revision int64
		var done bool
		var stage, next string
		if err := tx.QueryRow(ctx, `SELECT ocr_revision,invoice_completed_generation IS NOT DISTINCT FROM generation,stage,COALESCE(invoice_next_stage,'') FROM document_processing WHERE account_id=$1 AND document_id=$2`, j.AccountID, j.DocumentID).Scan(&revision, &done, &stage, &next); err != nil {
			return err
		}
		if revision != w.Revision {
			return document.ErrStaleJob
		}
		if done {
			return nil
		}
		if stage != "invoicing" || next != w.ResumeStage {
			return document.ErrStaleJob
		}
		if w.RemovePreviousAI {
			if _, err := tx.Exec(ctx, "DELETE FROM invoices WHERE account_id=$1 AND document_id=$2 AND source='ai'", j.AccountID, j.DocumentID); err != nil {
				return err
			}
		} else if v != nil && !w.Skipped {
			if err := saveRecord(ctx, tx, w, *v); err != nil {
				return err
			}
		}
		_, err := tx.Exec(ctx, `UPDATE document_processing SET invoice_completed_generation=generation,stage=$3,invoice_next_stage=NULL,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2`, j.AccountID, j.DocumentID, w.ResumeStage)
		return err
	})
}
