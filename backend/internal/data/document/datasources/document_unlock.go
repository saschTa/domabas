package datasources

import (
	"context"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func unlockReference(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id string, generation int64) (r.DocumentReferenceRecord, error) {
	if err := lockDocument(ctx, tx, a.AccountID, id); err != nil {
		return r.DocumentReferenceRecord{}, err
	}
	return readUnlockReference(ctx, tx, a, id, generation, true)
}
func readUnlockReference(ctx context.Context, tx pgx.Tx, a m.DocumentActor, id string, generation int64, lock bool) (r.DocumentReferenceRecord, error) {
	suffix := ""
	if lock {
		suffix = " FOR UPDATE"
	}
	var eligible bool
	if err := tx.QueryRow(ctx, "SELECT state='failed' AND failure_code='encrypted_pdf' AND generation=$3 FROM document_processing WHERE account_id=$1 AND document_id=$2"+suffix, a.AccountID, id, generation).Scan(&eligible); err != nil {
		return r.DocumentReferenceRecord{}, err
	}
	if !eligible {
		return r.DocumentReferenceRecord{}, m.ErrConflict
	}
	ref, err := fileReference(ctx, tx, a.AccountID, id)
	if err == nil && (ref.File.MediaType != "application/pdf" || ref.Location == "unlocked") {
		return ref, m.ErrConflict
	}
	return ref, err
}

func (s *DocumentDataSource) UnlockFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentUnlockFacts, error) {
	var facts m.DocumentUnlockFacts
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, "SELECT state,COALESCE(failure_code,''),generation FROM document_processing WHERE account_id=$1 AND document_id=$2", a.AccountID, id).Scan(&facts.State, &facts.FailureCode, &facts.Generation); err != nil {
			return err
		}
		record, err := fileReference(ctx, tx, a.AccountID, id)
		facts.Reference = m.DocumentFileReference{AccountID: record.AccountID, UploaderID: record.UploaderID, DocumentID: record.DocumentID, Location: record.Location, File: m.DocumentFile(record.File)}
		return err
	})
	return facts, err
}

func (s *DocumentDataSource) CompleteUnlockRecord(ctx context.Context, a m.DocumentActor, original, unlocked m.DocumentFileReference, generation int64, command m.DocumentRetryCommand) (r.DocumentProcessingRecord, error) {
	var result r.DocumentProcessingRecord
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		if _, err := prepareGeneration(ctx, tx); err != nil {
			return err
		}
		current, err := unlockReference(ctx, tx, a, original.DocumentID, generation)
		if err != nil {
			return err
		}
		if current.File.SHA256 != original.File.SHA256 || current.Location != original.Location || unlocked.AccountID != a.AccountID || unlocked.DocumentID != original.DocumentID || unlocked.UploaderID != current.UploaderID || unlocked.File.OriginalFilename != current.File.OriginalFilename || unlocked.File.MediaType != "application/pdf" || unlocked.Location != "unlocked" {
			return m.ErrConflict
		}
		if _, err = tx.Exec(ctx, "UPDATE document_files SET location='unlocked',size=$3,sha256=$4 WHERE account_id=$1 AND document_id=$2", a.AccountID, original.DocumentID, unlocked.File.Size, unlocked.File.SHA256); err != nil {
			return err
		}
		result, err = applyDocumentRetry(ctx, tx, a, original.DocumentID, command)
		return err
	})
	return result, err
}
