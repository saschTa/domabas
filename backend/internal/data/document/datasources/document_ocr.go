package datasources

import (
	"context"
	"encoding/json"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func lockDocument(ctx context.Context, tx pgx.Tx, account, id string) error {
	var locked string
	return tx.QueryRow(ctx, "SELECT id FROM documents WHERE account_id=$1 AND id=$2 FOR UPDATE", account, id).Scan(&locked)
}
func ocrRecord(ctx context.Context, tx pgx.Tx, account, id string) (r.DocumentOCRRecord, error) {
	result := r.DocumentOCRRecord{Status: "unavailable", SemanticIndexing: "unavailable"}
	var machine, manual *string
	var fileBacked bool
	var state string
	err := tx.QueryRow(ctx, `SELECT d.ocr_revision,d.ocr_machine_text,d.ocr_manual_text,f.document_id IS NOT NULL,COALESCE(p.state,'') FROM documents d LEFT JOIN document_files f ON f.account_id=d.account_id AND f.document_id=d.id LEFT JOIN document_processing p ON p.account_id=d.account_id AND p.document_id=d.id WHERE d.account_id=$1 AND d.id=$2`, account, id).Scan(&result.Revision, &machine, &manual, &fileBacked, &state)
	if err != nil {
		return result, err
	}
	reason := "no_original"
	if !fileBacked {
		result.Reason = &reason
		return result, nil
	}
	result.Text = machine
	origin := "machine"
	if manual != nil {
		result.Text = manual
		origin = "manual"
	}
	if result.Text == nil {
		switch state {
		case "queued", "processing":
			result.Status = "pending"
			reason = "processing"
		case "failed":
			reason = "processing_failed"
		default:
			reason = "legacy_text_missing"
		}
		result.Reason = &reason
		return result, nil
	}
	result.Status = "available"
	result.Origin = &origin
	configuration, err := readConfiguration(ctx, tx)
	if err != nil {
		return result, err
	}
	space, _ := json.Marshal(configuration.EmbeddingSpace())
	var count int
	var complete bool
	err = tx.QueryRow(ctx, `SELECT count(*),COALESCE(bool_and(c.embedding IS NOT NULL AND c.model_digest=($3::jsonb->>'Digest') AND p.configuration->>'EmbeddingModel'=($3::jsonb->>'Model') AND p.configuration->>'EmbeddingDigest'=($3::jsonb->>'Digest') AND (p.configuration->>'Dimensions')::integer=($3::jsonb->>'Dimensions')::integer AND p.configuration->>'EmbeddingInputRevision'=($3::jsonb->>'EmbeddingInputRevision') AND p.configuration->>'IndexingRevision'=($3::jsonb->>'IndexingRevision')),true) FROM document_chunks c JOIN document_processing p ON p.account_id=c.account_id AND p.document_id=c.document_id AND p.generation=c.generation WHERE c.account_id=$1 AND c.document_id=$2`, account, id, space).Scan(&count, &complete)
	if err != nil {
		return result, err
	}
	switch {
	case count == 0:
		result.SemanticIndexing = "not_required"
	case state == "failed":
		result.SemanticIndexing = "failed"
	case state == "ready" && complete:
		result.SemanticIndexing = "ready"
	default:
		result.SemanticIndexing = "pending"
	}
	return result, nil
}
func (s *DocumentDataSource) OCRRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentOCRRecord, error) {
	var result r.DocumentOCRRecord
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		result, err = ocrRecord(ctx, tx, a.AccountID, id)
		return err
	})
	return result, err
}
func replaceChunks(ctx context.Context, tx pgx.Tx, j m.DocumentJob, chunks []m.DocumentChunk) error {
	configuration, err := jobConfiguration(ctx, tx, j)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "DELETE FROM document_chunks WHERE account_id=$1 AND document_id=$2", j.AccountID, j.DocumentID); err != nil {
		return err
	}
	for i, chunk := range chunks {
		var digest *string
		if len(chunk.Vector) > 0 {
			value := configuration.EmbeddingDigest
			digest = &value
		}
		if _, err := tx.Exec(ctx, "INSERT INTO document_chunks(account_id,document_id,generation,position,content,embedding,model_digest) VALUES($1,$2,$3,$4,$5,$6,$7)", j.AccountID, j.DocumentID, j.Generation, i, chunk.Text, chunk.Vector, digest); err != nil {
			return err
		}
	}
	return nil
}
func (s *DocumentDataSource) CorrectionFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentCorrectionFacts, error) {
	var facts m.DocumentCorrectionFacts
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		facts.Configuration, err = readConfiguration(ctx, tx)
		if err != nil {
			return err
		}
		if err = tx.QueryRow(ctx, "SELECT ocr_revision FROM documents WHERE account_id=$1 AND id=$2", a.AccountID, id).Scan(&facts.Revision); err != nil {
			return err
		}
		err = tx.QueryRow(ctx, "SELECT p.generation,f.location FROM document_processing p JOIN document_files f ON f.account_id=p.account_id AND f.document_id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2", a.AccountID, id).Scan(&facts.Generation, &facts.Location)
		if err == pgx.ErrNoRows {
			return m.ErrConflict
		}
		return err
	})
	return facts, err
}
func (s *DocumentDataSource) CorrectOCRRecord(ctx context.Context, a m.DocumentActor, id string, input m.DocumentCorrectionCommand) (r.DocumentOCRRecord, error) {
	var result r.DocumentOCRRecord
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		c, err := prepareGeneration(ctx, tx)
		if err != nil {
			return err
		}
		if err := lockDocument(ctx, tx, a.AccountID, id); err != nil {
			return err
		}
		var revision, generation int64
		var location string
		var snapshot []byte
		if err := tx.QueryRow(ctx, "SELECT ocr_revision FROM documents WHERE account_id=$1 AND id=$2", a.AccountID, id).Scan(&revision); err != nil {
			return err
		}
		if revision != input.Expected.Revision {
			return m.ErrConflict
		}
		if err := tx.QueryRow(ctx, `SELECT p.generation,p.configuration,f.location FROM document_processing p JOIN document_files f ON f.account_id=p.account_id AND f.document_id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2 FOR UPDATE OF p`, a.AccountID, id).Scan(&generation, &snapshot, &location); err != nil {
			if err == pgx.ErrNoRows {
				return m.ErrConflict
			}
			return err
		}
		if generation != input.Expected.Generation || location != input.Expected.Location || c.Revision != input.Expected.Configuration.Revision || c.Fingerprint != input.Expected.Configuration.Fingerprint {
			return m.ErrConflict
		}
		snapshot, err = json.Marshal(c)
		if err != nil {
			return err
		}
		state, stage := input.State, input.Stage

		if _, err := tx.Exec(ctx, `UPDATE documents SET ocr_manual_text=$3,ocr_revision=ocr_revision+1 WHERE account_id=$1 AND id=$2`, a.AccountID, id, input.Text); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE document_processing SET split_pipeline=true,generation=generation+1,generation_sequence=nextval('document_processing_event_seq'),reason='ocr_correction',initiated_by_user_id=$8,parent_batch_id=NULL,extraction_method=NULL,extraction_engine=NULL,extraction_engine_version=NULL,requires_extraction=false,configuration_revision=$6,configuration=$7,ocr_revision=$3,state=$4,stage=$5,failure_code=NULL,updated_at=clock_timestamp(),delivery_deadline=NULL,processing_deadline=NULL,processing_started_at=NULL,unlimited_inference=false,workflow_id='',run_id='',next_check_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2`, a.AccountID, id, revision+1, state, stage, c.Revision, snapshot, a.UserID); err != nil {
			return err
		}
		j := m.DocumentJob{AccountID: a.AccountID, DocumentID: id, Generation: generation + 1}
		if err := replaceChunks(ctx, tx, j, input.Chunks); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "DELETE FROM document_outbox WHERE account_id=$1 AND document_id=$2", a.AccountID, id); err != nil {
			return err
		}
		if state != "ready" {
			if err := insertOutbox(ctx, tx, j, c); err != nil {
				return err
			}
		}
		result, err = ocrRecord(ctx, tx, a.AccountID, id)
		return err
	})
	return result, err
}
