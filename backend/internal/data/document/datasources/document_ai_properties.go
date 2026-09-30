package datasources

import (
	"context"
	"encoding/json"
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) aiPropertyWork(ctx context.Context, j m.DocumentJob) (r.DocumentPropertyWorkRecord, error) {
	var result r.DocumentPropertyWorkRecord
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		stage, err := lockAI(ctx, tx, j)
		if err != nil {
			return err
		}
		result.Eligible = true
		if stage == "complete" {
			result.Stage = stage
			return nil
		}
		if stage != "enriching" {
			return m.ErrStaleJob
		}
		var snapshot []byte
		if err = tx.QueryRow(ctx, `SELECT a.configuration,a.ocr_revision,d.metadata_revision,COALESCE(d.ocr_manual_text,d.ocr_machine_text,'') FROM document_ai_jobs a JOIN documents d ON d.account_id=a.account_id AND d.id=a.document_id WHERE a.account_id=$1 AND a.document_id=$2 AND a.attempt=$3`, j.AccountID, j.DocumentID, j.AIAttempt).Scan(&snapshot, &result.Revision, &result.MetadataRevision, &result.Text); err != nil {
			return err
		}
		var c m.DocumentProcessingConfiguration
		if err = json.Unmarshal(snapshot, &c); err != nil {
			return err
		}
		result.Configuration = r.DocumentLLMConfigurationRecord(c.LLM)
		result.Stage = stage
		result.Metadata, err = readDocument(ctx, tx, j.AccountID, j.DocumentID)
		return err
	})
	return result, err
}

func saveAIProperties(ctx context.Context, tx pgx.Tx, work m.DocumentPropertyWork, values m.DocumentMetadata) error {
	j := work.Job
	stage, err := lockAI(ctx, tx, j)
	if err != nil {
		return err
	}
	if stage == "complete" {
		return nil
	}
	if stage != "enriching" {
		return m.ErrStaleJob
	}
	var revision int64
	var snapshot []byte
	if err = tx.QueryRow(ctx, `SELECT ocr_revision,configuration FROM document_ai_jobs WHERE account_id=$1 AND document_id=$2 AND attempt=$3`, j.AccountID, j.DocumentID, j.AIAttempt).Scan(&revision, &snapshot); err != nil {
		return err
	}
	var c m.DocumentProcessingConfiguration
	if err = json.Unmarshal(snapshot, &c); err != nil {
		return err
	}
	if revision != work.Revision || !c.LLM.Equal(work.Configuration) {
		return m.ErrStaleJob
	}
	_, err = tx.Exec(ctx, `UPDATE documents SET description=$4,tags=$5,sender=$6,recipients=$7,document_date=NULLIF($8,'')::date,subject=$9 WHERE account_id=$1 AND id=$2 AND metadata_revision=$3`, j.AccountID, j.DocumentID, work.MetadataRevision, values.Description, values.Tags, values.Sender, values.Recipients, values.DocumentDate, values.Subject)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE document_ai_jobs SET stage=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND attempt=$3`, j.AccountID, j.DocumentID, j.AIAttempt, work.NextStage)
	return err
}
