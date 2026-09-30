package datasources

import (
	"context"
	"encoding/json"
	"slices"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func lockJob(ctx context.Context, tx pgx.Tx, j m.DocumentJob) (string, error) {
	if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
		return "", staleError(err)
	}
	var stage string
	err := tx.QueryRow(ctx, `SELECT stage FROM document_processing WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND ocr_revision=(SELECT ocr_revision FROM documents WHERE account_id=$1 AND id=$2) AND state IN ('queued','processing') AND delivery_deadline IS NOT NULL AND ((processing_deadline IS NULL AND (delivery_deadline>clock_timestamp() OR (unlimited_inference AND processing_started_at IS NOT NULL))) OR processing_deadline>clock_timestamp()) FOR UPDATE`, j.AccountID, j.DocumentID, j.Generation).Scan(&stage)
	return stage, staleError(err)
}
func lockRevision(ctx context.Context, tx pgx.Tx, j m.DocumentJob, revision int64) error {
	var current int64
	if err := tx.QueryRow(ctx, "SELECT ocr_revision FROM document_processing WHERE account_id=$1 AND document_id=$2 AND generation=$3", j.AccountID, j.DocumentID, j.Generation).Scan(&current); err != nil {
		return staleError(err)
	}
	if current != revision {
		return m.ErrStaleJob
	}
	return nil
}
func (s *DocumentDataSource) WorkRecord(ctx context.Context, j m.DocumentJob, _ string) (r.DocumentWorkRecord, error) {
	result := r.DocumentWorkRecord{Job: r.DocumentJobRecord(j)}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
			return staleError(err)
		}
		var snapshot []byte
		err := tx.QueryRow(ctx, `SELECT p.state,p.stage,p.configuration,p.ocr_revision,p.unlimited_inference,p.split_pipeline,d.ocr_manual_text,
   p.state IN ('queued','processing') AND p.delivery_deadline IS NOT NULL AND ((p.processing_deadline IS NULL AND (p.delivery_deadline>clock_timestamp() OR (p.unlimited_inference AND p.processing_started_at IS NOT NULL))) OR p.processing_deadline>clock_timestamp()),
   COALESCE((SELECT bool_and(c.embedding IS NOT NULL AND c.model_digest=p.configuration->>'EmbeddingDigest') FROM document_chunks c WHERE c.account_id=p.account_id AND c.document_id=p.document_id AND c.generation=p.generation),true)
   FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2 AND p.generation=$3 AND p.ocr_revision=d.ocr_revision FOR UPDATE OF p`, j.AccountID, j.DocumentID, j.Generation).Scan(&result.State, &result.Stage, &snapshot, &result.Revision, &result.UnlimitedInference, &result.SplitPipeline, &result.ManualText, &result.Eligible, &result.EmbeddingsComplete)
		if err != nil {
			return staleError(err)
		}
		if err = json.Unmarshal(snapshot, &result.Configuration); err != nil {
			return err
		}
		result.Reference, err = fileReference(ctx, tx, j.AccountID, j.DocumentID)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, "SELECT position,content,embedding FROM document_chunks WHERE account_id=$1 AND document_id=$2 AND generation=$3 ORDER BY position", j.AccountID, j.DocumentID, j.Generation)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var chunk r.DocumentChunkRecord
			if err = rows.Scan(&chunk.Position, &chunk.Text, &chunk.Vector); err != nil {
				return err
			}
			result.Chunks = append(result.Chunks, chunk)
		}
		return rows.Err()
	})
	return result, err
}
func (s *DocumentDataSource) BeginWork(ctx context.Context, command m.DocumentProcessingCommand) error {
	w := command.Expected
	j := w.Job
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if command.Replay {
			if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
				return staleError(err)
			}
			var present bool
			err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2 AND p.generation=$3 AND p.ocr_revision=$4 AND p.ocr_revision=d.ocr_revision AND p.state=$5 AND p.stage=$6)`, j.AccountID, j.DocumentID, j.Generation, w.Revision, w.State, w.Stage).Scan(&present)
			if err == nil && !present {
				return m.ErrStaleJob
			}
			return err
		}
		if err := fenceProcessingWork(ctx, tx, w); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE document_processing SET state=$4,stage=$5,processing_deadline=CASE WHEN $6 THEN NULL ELSE COALESCE(processing_deadline,clock_timestamp()+make_interval(secs=>$7)) END,processing_started_at=COALESCE(processing_started_at,clock_timestamp()),updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3`, j.AccountID, j.DocumentID, j.Generation, command.State, command.Stage, command.Unlimited, command.Deadline.Seconds())
		return err
	})
}
func fenceProcessingWork(ctx context.Context, tx pgx.Tx, w m.DocumentProcessingWork) error {
	j := w.Job
	stage, err := lockJob(ctx, tx, j)
	if err != nil {
		return err
	}
	if stage != w.Stage {
		return m.ErrStaleJob
	}
	if err = lockRevision(ctx, tx, j, w.Revision); err != nil {
		return err
	}
	configuration, err := jobConfiguration(ctx, tx, j)
	if err != nil {
		return err
	}
	if configuration.Fingerprint != w.Configuration.Fingerprint || configuration.Revision != w.Configuration.Revision || configuration.LLM.Enabled != w.Configuration.LLM.Enabled {
		return m.ErrStaleJob
	}
	var state string
	var manual *string
	var split, unlimited bool
	if err = tx.QueryRow(ctx, `SELECT p.state,p.split_pipeline,p.unlimited_inference,d.ocr_manual_text FROM document_processing p JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2`, j.AccountID, j.DocumentID).Scan(&state, &split, &unlimited, &manual); err != nil {
		return err
	}
	if state != w.State || split != w.SplitPipeline || unlimited != w.UnlimitedInference || (manual == nil) != (w.ManualText == nil) || (manual != nil && *manual != *w.ManualText) {
		return m.ErrStaleJob
	}
	ref, err := fileReference(ctx, tx, j.AccountID, j.DocumentID)
	if err != nil {
		return staleError(err)
	}
	if ref.Location != w.Reference.Location || ref.AccountID != w.Reference.AccountID || ref.UploaderID != w.Reference.UploaderID || ref.DocumentID != w.Reference.DocumentID || ref.File.Size != w.Reference.File.Size || ref.File.SHA256 != w.Reference.File.SHA256 || ref.File.MediaType != w.Reference.File.MediaType {
		return m.ErrStaleJob
	}
	return nil
}
func (s *DocumentDataSource) SaveExtractionEvidence(ctx context.Context, command m.DocumentExtractionCommand) error {
	j := command.Expected.Job
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		stage, err := lockJob(ctx, tx, j)
		if err != nil {
			return err
		}
		if slices.Contains(command.ReplayStages, stage) {
			return nil
		}
		if err = fenceProcessingWork(ctx, tx, command.Expected); err != nil {
			return err
		}
		identity := command.Identity
		if _, err = tx.Exec(ctx, `UPDATE documents d SET ocr_machine_text=$3,ocr_revision=$4,machine_extraction_fingerprint=p.configuration->>'Fingerprint',machine_extraction_sequence=p.generation_sequence,machine_extracted_at=clock_timestamp(),machine_extraction_method=$5,machine_extraction_engine=$6,machine_extraction_engine_version=$7 FROM document_processing p WHERE d.account_id=$1 AND d.id=$2 AND p.account_id=d.account_id AND p.document_id=d.id`, j.AccountID, j.DocumentID, command.Extraction.Text, command.Revision, identity.Method, identity.Engine, identity.EngineVersion); err != nil {
			return err
		}
		if err = replaceChunks(ctx, tx, j, command.Chunks); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "UPDATE document_processing SET invoice_failure_code=NULLIF($10,''),invoice_xml=$9,invoice_completed_generation=NULL,invoice_next_stage=NULL,stage=$4,ocr_revision=$5,updated_at=clock_timestamp(),extraction_method=$6,extraction_engine=$7,extraction_engine_version=$8 WHERE account_id=$1 AND document_id=$2 AND generation=$3", j.AccountID, j.DocumentID, j.Generation, command.Stage, command.Revision, identity.Method, identity.Engine, identity.EngineVersion, command.Extraction.InvoiceXML, command.Extraction.InvoiceFailureCode)
		return err
	})
}
func (s *DocumentDataSource) SaveEmbeddings(ctx context.Context, command m.DocumentEmbeddingCommand) error {
	j := command.Expected.Job
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		stage, err := lockJob(ctx, tx, j)
		if err != nil {
			return err
		}
		if err = lockRevision(ctx, tx, j, command.Expected.Revision); err != nil {
			return err
		}
		if slices.Contains(command.ReplayStages, stage) {
			return nil
		}
		if err = fenceProcessingWork(ctx, tx, command.Expected); err != nil {
			return err
		}
		if err = replaceChunks(ctx, tx, j, command.Chunks); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "UPDATE document_processing SET stage=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3", j.AccountID, j.DocumentID, j.Generation, command.Stage)
		return err
	})
}
func (s *DocumentDataSource) Publish(ctx context.Context, command m.DocumentPublicationCommand) error {
	j := command.Expected.Job
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := fenceProcessingWork(ctx, tx, command.Expected); err != nil {
			return err
		}
		var complete bool
		if err := tx.QueryRow(ctx, "SELECT COALESCE(bool_and(embedding IS NOT NULL AND model_digest=$4),true) FROM document_chunks WHERE account_id=$1 AND document_id=$2 AND generation=$3", j.AccountID, j.DocumentID, j.Generation, command.Digest).Scan(&complete); err != nil {
			return err
		}
		if !complete {
			return m.ErrStaleJob
		}
		ref, err := fileReference(ctx, tx, j.AccountID, j.DocumentID)
		if err != nil {
			return staleError(err)
		}
		if ref.Location == "staged" {
			if s.publication == nil {
				return m.DocumentProcessingError{Code: "storage_unavailable", Retryable: true}
			}
			value := r.DocumentContentReference{AccountID: ref.AccountID, UploaderID: ref.UploaderID, DocumentID: ref.DocumentID, Location: ref.Location, OriginalFilename: ref.File.OriginalFilename, MediaType: ref.File.MediaType, SHA256: ref.File.SHA256, Size: ref.File.Size, IngestedAt: ref.File.IngestedAt}
			promoted, err := s.publication.Promote(ctx, value)
			if err != nil {
				return m.DocumentProcessingError{Code: "storage_unavailable", Retryable: true}
			}
			if promoted.Location != command.Location || promoted.AccountID != value.AccountID || promoted.UploaderID != value.UploaderID || promoted.DocumentID != value.DocumentID || promoted.Size != value.Size || promoted.SHA256 != value.SHA256 {
				return m.ErrStaleJob
			}
		}
		if _, err = tx.Exec(ctx, "UPDATE document_files SET location=$3 WHERE account_id=$1 AND document_id=$2 AND location='staged'", j.AccountID, j.DocumentID, command.Location); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "UPDATE document_processing SET state=$4,stage=$5,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3", j.AccountID, j.DocumentID, j.Generation, command.State, command.Stage)
		return err
	})
}
func (s *DocumentDataSource) Fail(ctx context.Context, j m.DocumentJob, code string) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
			return staleError(err)
		}
		tag, err := tx.Exec(ctx, `UPDATE document_processing SET state='failed',stage='failed',failure_code=$4,updated_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2 AND generation=$3 AND ocr_revision=(SELECT ocr_revision FROM documents WHERE account_id=$1 AND id=$2) AND state IN ('queued','processing')`, j.AccountID, j.DocumentID, j.Generation, code)
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrStaleJob
		}
		return err
	})
}

func jobConfiguration(ctx context.Context, tx pgx.Tx, j m.DocumentJob) (m.DocumentProcessingConfiguration, error) {
	var snapshot []byte
	var c m.DocumentProcessingConfiguration
	err := tx.QueryRow(ctx, `SELECT configuration FROM document_processing WHERE account_id=$1 AND document_id=$2 AND generation=$3`, j.AccountID, j.DocumentID, j.Generation).Scan(&snapshot)
	if err != nil {
		return c, staleError(err)
	}
	if err = json.Unmarshal(snapshot, &c); err != nil {
		return c, err
	}
	fingerprint, err := c.CanonicalFingerprint()
	if err != nil {
		return c, err
	}
	if c.Fingerprint != fingerprint {
		return c, m.DocumentProcessingError{Code: "configuration_unavailable"}
	}
	return c, nil
}
