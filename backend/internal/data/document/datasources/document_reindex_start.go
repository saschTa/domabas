package datasources

import (
	"context"
	"errors"
	"reflect"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) ReindexStartFacts(ctx context.Context, a m.DocumentActor, system bool, request string) (m.DocumentReindexStartFacts, error) {
	var facts m.DocumentReindexStartFacts
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		facts, err = readReindexStartFacts(ctx, tx, a, system, request)
		return err
	})
	return facts, err
}

func readReindexStartFacts(ctx context.Context, tx pgx.Tx, a m.DocumentActor, system bool, request string) (m.DocumentReindexStartFacts, error) {
	var facts m.DocumentReindexStartFacts
	configuration, err := readConfiguration(ctx, tx)
	if err != nil {
		return facts, err
	}
	facts.ConfigurationRevision = configuration.Revision
	facts.ConfigurationFingerprint = configuration.Fingerprint
	existing := m.DocumentReindexExistingRequest{}
	err = tx.QueryRow(ctx, `SELECT account_id::text,requester_id::text,configuration_revision FROM document_reindex_batches WHERE id=$1`, request).Scan(&existing.AccountID, &existing.RequesterID, &existing.ConfigurationRevision)
	if err == nil {
		facts.Existing = &existing
		return facts, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return facts, err
	}
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM document_reindex_batches WHERE account_id IS NOT DISTINCT FROM $1::uuid AND configuration_revision=$2 AND reason='manual' AND status IN ('enumerating','running'))`, batchScope(a, system), configuration.Revision).Scan(&facts.Active)
	return facts, err
}

func (s *DocumentDataSource) CreateBatchRecord(ctx context.Context, a m.DocumentActor, system bool, command m.DocumentReindexStartCommand) (r.DocumentReindexBatchRecord, error) {
	var out r.DocumentReindexBatchRecord
	err := s.scopedWriteTx(ctx, a, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		facts, err := readReindexStartFacts(ctx, tx, a, system, command.Request.RequestID)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(facts, command.Expected) {
			return m.ErrConflict
		}
		if command.Replay {
			out, err = scanBatch(tx.QueryRow(ctx, "SELECT "+batchColumns+" FROM document_reindex_batches WHERE id=$1", command.Request.RequestID))
			return err
		}
		out, err = scanBatch(tx.QueryRow(ctx, `INSERT INTO document_reindex_batches(id,account_id,requester_id,reason,configuration_revision,configuration_fingerprint,cutoff_sequence) VALUES($1,$2,$3,'manual',$4,$5,nextval('document_processing_event_seq')) RETURNING `+batchColumns, command.Request.RequestID, batchScope(a, system), a.UserID, facts.ConfigurationRevision, facts.ConfigurationFingerprint))
		return err
	})
	return out, err
}
