package datasources

import (
	"context"
	"encoding/json"
	"errors"
	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/jackc/pgx/v5"
)

func activeAI(ctx context.Context, tx pgx.Tx, j document.DocumentJob) error {
	var id string
	err := tx.QueryRow(ctx, `SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE`, j.AccountID, j.DocumentID).Scan(&id)
	if err == nil {
		err = tx.QueryRow(ctx, `SELECT a.document_id FROM document_ai_jobs a JOIN document_processing p ON p.account_id=a.account_id AND p.document_id=a.document_id AND p.generation=a.generation AND p.ocr_revision=a.ocr_revision JOIN documents d ON d.account_id=a.account_id AND d.id=a.document_id AND d.ocr_revision=a.ocr_revision WHERE a.account_id=$1 AND a.document_id=$2 AND a.generation=$3 AND a.attempt=$4 AND p.state='ready' AND a.status IN ('queued','running') AND a.attempt=(SELECT max(attempt) FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2) FOR UPDATE OF a`, j.AccountID, j.DocumentID, j.Generation, j.AIAttempt).Scan(&id)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return document.ErrStaleJob
	}
	return err
}

func (s *InvoiceDataSource) aiWork(ctx context.Context, j document.DocumentJob) (m.InvoiceWork, error) {
	result := m.InvoiceWork{Job: j}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := activeAI(ctx, tx, j); err != nil {
			return err
		}
		var config []byte
		err := tx.QueryRow(ctx, `SELECT a.ocr_revision,a.invoice_done,a.stage,a.invoice_classifier_version,COALESCE(a.invoice_decision,''),COALESCE(a.invoice_decision_reason,''),a.invoice_classification_pass,a.invoice_input_characters,a.invoice_source_characters,p.invoice_xml,COALESCE(p.invoice_failure_code,''),a.configuration,f.media_type,COALESCE(d.ocr_manual_text,d.ocr_machine_text,'') FROM document_ai_jobs a JOIN document_processing p ON p.account_id=a.account_id AND p.document_id=a.document_id JOIN documents d ON d.account_id=a.account_id AND d.id=a.document_id JOIN document_files f ON f.account_id=a.account_id AND f.document_id=a.document_id WHERE a.account_id=$1 AND a.document_id=$2 AND a.attempt=$3`, j.AccountID, j.DocumentID, j.AIAttempt).Scan(&result.Revision, &result.Done, &result.Stage, &result.ClassifierVersion, &result.Classification.Decision, &result.Classification.Reason, &result.Classification.Pass, &result.Classification.InputCharacters, &result.Classification.SourceCharacters, &result.XML, &result.SourceFailureCode, &config, &result.MediaType, &result.Text)
		if err != nil {
			return err
		}
		var c document.DocumentProcessingConfiguration
		if err = json.Unmarshal(config, &c); err != nil {
			return err
		}
		result.Configuration = c.LLM
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

func (s *InvoiceDataSource) aiSave(ctx context.Context, w m.InvoiceWork, v *r.InvoiceRecord) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		j := w.Job
		if err := activeAI(ctx, tx, j); err != nil {
			return err
		}
		var revision int64
		var done bool
		var stage string
		if err := tx.QueryRow(ctx, `SELECT ocr_revision,invoice_done,stage FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND attempt=$3`, j.AccountID, j.DocumentID, j.AIAttempt).Scan(&revision, &done, &stage); err != nil {
			return err
		}
		if revision != w.Revision {
			return document.ErrStaleJob
		}
		if done {
			return nil
		}
		if stage != "invoicing" {
			return document.ErrStaleJob
		}
		if !w.Skipped {
			if w.RemovePreviousAI {
				if _, err := tx.Exec(ctx, "DELETE FROM invoices WHERE account_id=$1 AND document_id=$2 AND source='ai'", j.AccountID, j.DocumentID); err != nil {
					return err
				}
			} else if v != nil {
				if err := saveRecord(ctx, tx, w, *v); err != nil {
					return err
				}
			}
		}
		_, err := tx.Exec(ctx, `UPDATE document_ai_jobs SET invoice_done=true,stage=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND attempt=$3`, j.AccountID, j.DocumentID, j.AIAttempt, w.ResumeStage)
		return err
	})
}
