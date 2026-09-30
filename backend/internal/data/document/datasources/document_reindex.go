package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func sweepProcessingOrphans(ctx context.Context, tx pgx.Tx) error {
	queries := []string{
		`DELETE FROM document_processing_jobs WHERE id IN(SELECT j.id FROM document_processing_jobs j WHERE NOT EXISTS(SELECT 1 FROM accounts a WHERE a.id=j.account_id) LIMIT 100)`,
		`DELETE FROM document_reindex_items WHERE (batch_id,document_id) IN(SELECT i.batch_id,i.document_id FROM document_reindex_items i WHERE NOT EXISTS(SELECT 1 FROM accounts a WHERE a.id=i.account_id) LIMIT 100)`,
		`DELETE FROM document_reindex_batches b WHERE b.id IN(SELECT id FROM document_reindex_batches b WHERE b.account_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts a WHERE a.id=b.account_id) AND NOT EXISTS(SELECT 1 FROM document_reindex_items i WHERE i.batch_id=b.id) LIMIT 100)`,
		`UPDATE document_reindex_batches SET requester_id=NULL WHERE id IN(SELECT b.id FROM document_reindex_batches b WHERE requester_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id=b.requester_id) LIMIT 100)`,
	}
	var err error
	for _, query := range queries {
		if _, err = tx.Exec(ctx, query); err != nil {
			return err
		}
	}
	return nil
}
func scheduleReindex(ctx context.Context, tx pgx.Tx, commands []m.DocumentReindexScheduleCommand) (*r.DocumentLeaseRecord, string, error) {
	candidates, err := readReindexIntents(ctx, tx, true)
	if err != nil {
		return nil, "", err
	}
	for _, intent := range candidates {
		var command *m.DocumentReindexScheduleCommand
		for index := range commands {
			candidate := &commands[index]
			if candidate.Expected.BatchID == intent.BatchID && candidate.Expected.DocumentID == intent.DocumentID {
				command = candidate
				break
			}
		}
		if command == nil {
			continue
		}
		if _, err = tx.Exec(ctx, "UPDATE document_reindex_items SET next_check_at=clock_timestamp()+$3*interval '1 second' WHERE batch_id=$1 AND document_id=$2", intent.BatchID, intent.DocumentID, command.RecheckAfter.Seconds()); err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, "UPDATE document_reindex_batches SET last_served_at=clock_timestamp() WHERE id=$1", intent.BatchID); err != nil {
			return nil, "", err
		}
		v, available, err := readReindexCandidate(ctx, tx, intent, true)
		if err != nil {
			return nil, "", err
		}
		if !available || !reflect.DeepEqual(v, command.Expected) {
			continue
		}
		switch command.Action {
		case "skip":
			if _, err = tx.Exec(ctx, "UPDATE document_reindex_items SET status=$3,outcome_code=$4 WHERE batch_id=$1 AND document_id=$2", v.BatchID, v.DocumentID, command.Status, command.OutcomeCode); err != nil {
				return nil, "", err
			}
			continue
		case "reuse":
			if _, err = tx.Exec(ctx, "UPDATE document_reindex_items SET status=$3,job_id=$4,generation=$5 WHERE batch_id=$1 AND document_id=$2", v.BatchID, v.DocumentID, command.Status, v.JobID, v.Generation); err != nil {
				return nil, "", err
			}
			continue
		case "enqueue":
		default:
			continue
		}
		c, generation := v.Configuration, v.Generation
		snapshot, err := json.Marshal(c)
		if err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_processing SET split_pipeline=true,generation=generation+1,generation_sequence=nextval('document_processing_event_seq'),requires_extraction=true,reason='reindex',initiated_by_user_id=(SELECT requester_id FROM document_reindex_batches WHERE id=$5),parent_batch_id=$5,extraction_method=NULL,extraction_engine=NULL,extraction_engine_version=NULL,ocr_revision=(SELECT ocr_revision FROM documents WHERE id=$2 AND account_id=$1),state='queued',stage='queued',configuration_revision=$3,configuration=$4,failure_code=NULL,updated_at=clock_timestamp(),delivery_deadline=NULL,processing_deadline=NULL,processing_started_at=NULL,unlimited_inference=false,workflow_id='',run_id='',next_check_at=clock_timestamp() WHERE account_id=$1 AND document_id=$2`, v.AccountID, v.DocumentID, c.Revision, snapshot, v.BatchID); err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, `DELETE FROM document_chunks WHERE account_id=$1 AND document_id=$2 AND generation<>$3`, v.AccountID, v.DocumentID, generation); err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_chunks SET generation=$3,embedding=NULL,model_digest=NULL WHERE account_id=$1 AND document_id=$2`, v.AccountID, v.DocumentID, generation+1); err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, `DELETE FROM document_outbox WHERE account_id=$1 AND document_id=$2`, v.AccountID, v.DocumentID); err != nil {
			return nil, "", err
		}
		job := m.DocumentJob{AccountID: v.AccountID, DocumentID: v.DocumentID, Generation: generation + 1}
		if err = insertOutbox(ctx, tx, job, c); err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_reindex_items SET status='running',generation=$3,job_id=(SELECT id FROM document_processing_jobs WHERE account_id=$4 AND document_id=$2 AND generation=$3) WHERE batch_id=$1 AND document_id=$2`, v.BatchID, v.DocumentID, generation+1, v.AccountID); err != nil {
			return nil, "", err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_reindex_batches SET last_served_at=clock_timestamp() WHERE id=$1`, v.BatchID); err != nil {
			return nil, "", err
		}
		out := &r.DocumentLeaseRecord{Job: r.DocumentJobRecord(job), ConfigurationRevision: c.Revision}
		if err = tx.QueryRow(ctx, `SELECT id FROM document_outbox WHERE account_id=$1 AND document_id=$2 AND generation=$3`, v.AccountID, v.DocumentID, generation+1).Scan(&out.ID); err != nil {
			return nil, "", err
		}
		return out, v.BatchID, nil
	}
	return nil, "", nil
}

func (s *DocumentDataSource) ReindexScheduleFacts(ctx context.Context) ([]m.DocumentReindexScheduleFacts, error) {
	result := []m.DocumentReindexScheduleFacts{}
	err := pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		intents, err := readReindexIntents(ctx, tx, false)
		if err != nil {
			return err
		}
		for _, intent := range intents {
			candidate, _, err := readReindexCandidate(ctx, tx, intent, false)
			if err != nil {
				return err
			}
			result = append(result, candidate)
		}
		return nil
	})
	return result, err
}

func readReindexIntents(ctx context.Context, tx pgx.Tx, lock bool) ([]m.DocumentReindexScheduleFacts, error) {
	query := `SELECT b.id,i.account_id,i.document_id,b.reason,b.cutoff_sequence,b.configuration_revision FROM document_reindex_batches b JOIN document_reindex_items i ON i.batch_id=b.id WHERE b.status IN ('enumerating','running') AND i.status='waiting' AND i.next_check_at<=clock_timestamp() AND NOT EXISTS(SELECT 1 FROM document_processing_executions e WHERE e.account_id=i.account_id AND e.document_id=i.document_id AND e.closed_at IS NULL) ORDER BY b.last_served_at NULLS FIRST,b.created_at,b.id,i.next_check_at,i.document_id LIMIT 20`
	if lock {
		query += " FOR UPDATE OF b,i"
	}
	rows, err := tx.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	values := []m.DocumentReindexScheduleFacts{}
	for rows.Next() {
		var v m.DocumentReindexScheduleFacts
		if err := rows.Scan(&v.BatchID, &v.AccountID, &v.DocumentID, &v.Reason, &v.Cutoff, &v.ConfigurationRevision); err != nil {
			return nil, err
		}
		values = append(values, v)
	}
	return values, rows.Err()
}

func readReindexCandidate(ctx context.Context, tx pgx.Tx, v m.DocumentReindexScheduleFacts, lock bool) (m.DocumentReindexScheduleFacts, bool, error) {
	var snapshot []byte
	if err := tx.QueryRow(ctx, "SELECT configuration FROM document_processing_configurations WHERE revision=$1", v.ConfigurationRevision).Scan(&snapshot); err != nil {
		return v, false, err
	}
	if err := json.Unmarshal(snapshot, &v.Configuration); err != nil {
		return v, false, err
	}
	query := "SELECT id FROM documents WHERE account_id=$1 AND id=$2"
	if lock {
		query += " FOR UPDATE SKIP LOCKED"
	}
	var id string
	err := tx.QueryRow(ctx, query, v.AccountID, v.DocumentID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		if lock {
			var exists bool
			if err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM documents WHERE account_id=$1 AND id=$2)", v.AccountID, v.DocumentID).Scan(&exists); err != nil {
				return v, false, err
			}
			if exists {
				return v, false, nil
			}
		}
		return v, true, nil
	}
	if err != nil {
		return v, false, err
	}
	v.Exists = true
	query = `SELECT p.state,p.generation,p.configuration->>'Fingerprint',j.id,j.status,j.generation_sequence,j.requires_extraction,d.machine_extraction_fingerprint FROM document_processing p JOIN document_processing_jobs j ON j.account_id=p.account_id AND j.document_id=p.document_id AND j.generation=p.generation JOIN documents d ON d.id=p.document_id JOIN document_files f ON f.document_id=p.document_id WHERE p.account_id=$1 AND p.document_id=$2`
	if lock {
		query += " FOR UPDATE OF p"
	}
	err = tx.QueryRow(ctx, query, v.AccountID, v.DocumentID).Scan(&v.ProcessingState, &v.Generation, &v.Fingerprint, &v.JobID, &v.JobStatus, &v.Sequence, &v.Extraction, &v.MachineFingerprint)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, true, nil
	}
	if err != nil {
		return v, false, err
	}
	v.Original = true
	return v, true, nil
}
