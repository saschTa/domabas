package datasources

import (
	"context"
	"errors"
	"reflect"
	"slices"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func (s *DocumentDataSource) ReindexMaintenanceFacts(ctx context.Context) (m.DocumentReindexMaintenanceFacts, error) {
	var facts m.DocumentReindexMaintenanceFacts
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		if err := sweepProcessingOrphans(ctx, tx); err != nil {
			return err
		}
		var err error
		facts, err = readReindexMaintenanceFacts(ctx, tx)
		return err
	})
	return facts, err
}

func readReindexMaintenanceFacts(ctx context.Context, tx pgx.Tx) (m.DocumentReindexMaintenanceFacts, error) {
	facts := m.DocumentReindexMaintenanceFacts{Outcomes: []m.DocumentReindexOutcomeFacts{}, Aggregates: []m.DocumentReindexAggregateFacts{}}
	enumeration := m.DocumentReindexEnumeration{Candidates: []m.DocumentReindexCandidate{}}
	err := tx.QueryRow(ctx, `SELECT id,account_id::text,cutoff_sequence,cursor_sequence FROM document_reindex_batches WHERE NOT enumeration_complete AND status='enumerating' ORDER BY last_served_at NULLS FIRST,created_at,id LIMIT 1`).Scan(&enumeration.BatchID, &enumeration.AccountID, &enumeration.Cutoff, &enumeration.Cursor)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return facts, err
	}
	affected := map[string]bool{}
	if err == nil {
		rows, err := tx.Query(ctx, `SELECT d.id,d.account_id,d.accepted_sequence,f.document_id IS NOT NULL,EXISTS(SELECT 1 FROM document_reindex_items i WHERE i.batch_id=$4 AND i.document_id=d.id) FROM documents d LEFT JOIN document_files f ON f.document_id=d.id AND f.account_id=d.account_id WHERE d.account_id IS NOT NULL AND ($1::uuid IS NULL OR d.account_id=$1) AND d.accepted_sequence>$2 AND d.accepted_sequence<$3 ORDER BY d.accepted_sequence,d.id LIMIT 100`, enumeration.AccountID, enumeration.Cursor, enumeration.Cutoff, enumeration.BatchID)
		if err != nil {
			return facts, err
		}
		for rows.Next() {
			var candidate m.DocumentReindexCandidate
			if err := rows.Scan(&candidate.ID, &candidate.AccountID, &candidate.Sequence, &candidate.Original, &candidate.AlreadyEnrolled); err != nil {
				rows.Close()
				return facts, err
			}
			enumeration.Candidates = append(enumeration.Candidates, candidate)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return facts, err
		}
		facts.Enumeration = &enumeration
		affected[enumeration.BatchID] = true
	}
	rows, err := tx.Query(ctx, `SELECT i.batch_id,i.document_id,i.status,b.status,COALESCE(j.status,''),j.failure_code,d.id IS NULL FROM document_reindex_items i JOIN document_reindex_batches b ON b.id=i.batch_id LEFT JOIN document_processing_jobs j ON j.id=i.job_id LEFT JOIN documents d ON d.id=i.document_id AND d.account_id=i.account_id WHERE i.next_check_at<=clock_timestamp() AND (i.status='running' OR (i.status='waiting' AND b.status='superseded')) ORDER BY b.last_served_at NULLS FIRST,b.created_at,i.document_id LIMIT 100`)
	if err != nil {
		return facts, err
	}
	for rows.Next() {
		var outcome m.DocumentReindexOutcomeFacts
		if err := rows.Scan(&outcome.BatchID, &outcome.DocumentID, &outcome.ItemStatus, &outcome.BatchStatus, &outcome.JobStatus, &outcome.FailureCode, &outcome.Deleted); err != nil {
			rows.Close()
			return facts, err
		}
		facts.Outcomes = append(facts.Outcomes, outcome)
		affected[outcome.BatchID] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return facts, err
	}
	var dirty string
	err = tx.QueryRow(ctx, `SELECT id FROM document_reindex_batches WHERE needs_aggregation ORDER BY created_at,id LIMIT 1`).Scan(&dirty)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return facts, err
	}
	if err == nil {
		affected[dirty] = true
	}
	ids := make([]string, 0, len(affected))
	for id := range affected {
		ids = append(ids, id)
	}
	slices.Sort(ids)
	for _, id := range ids {
		aggregate := m.DocumentReindexAggregateFacts{BatchID: id}
		err := tx.QueryRow(ctx, `SELECT b.status,b.enumeration_complete,count(i.document_id),count(*) FILTER(WHERE i.status='waiting'),count(*) FILTER(WHERE i.status='running'),count(*) FILTER(WHERE i.status='succeeded'),count(*) FILTER(WHERE i.status='failed'),count(*) FILTER(WHERE i.status='skipped'),count(*) FILTER(WHERE i.status='superseded') FROM document_reindex_batches b LEFT JOIN document_reindex_items i ON i.batch_id=b.id WHERE b.id=$1 GROUP BY b.id`, id).Scan(&aggregate.Status, &aggregate.EnumerationComplete, &aggregate.Counts.Discovered, &aggregate.Counts.Waiting, &aggregate.Counts.Running, &aggregate.Counts.Succeeded, &aggregate.Counts.Failed, &aggregate.Counts.Skipped, &aggregate.Counts.Superseded)
		if err != nil {
			return facts, err
		}
		facts.Aggregates = append(facts.Aggregates, aggregate)
	}
	return facts, nil
}

func (s *DocumentDataSource) MaintainProcessing(ctx context.Context, command m.DocumentReindexMaintenanceCommand) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := coordinate(ctx, tx); err != nil {
			return err
		}
		current, err := readReindexMaintenanceFacts(ctx, tx)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(current, command.Expected) {
			return m.ErrConflict
		}
		for _, item := range command.Insertions {
			if _, err := tx.Exec(ctx, `INSERT INTO document_reindex_items(batch_id,account_id,document_id,status,outcome_code) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, item.BatchID, item.AccountID, item.DocumentID, item.Status, item.OutcomeCode); err != nil {
				return err
			}
		}
		if enumeration := command.Expected.Enumeration; enumeration != nil {
			if _, err := tx.Exec(ctx, `UPDATE document_reindex_batches SET cursor_sequence=$2,enumeration_complete=$3,status=$4,last_served_at=clock_timestamp() WHERE id=$1`, enumeration.BatchID, command.Cursor, command.EnumerationComplete, command.EnumerationStatus); err != nil {
				return err
			}
		}
		for _, item := range command.Outcomes {
			if _, err := tx.Exec(ctx, `UPDATE document_reindex_items SET status=$3,outcome_code=$4,job_id=CASE WHEN $5 THEN NULL ELSE job_id END,generation=CASE WHEN $5 THEN NULL ELSE generation END,next_check_at=clock_timestamp()+$6*interval '1 second' WHERE batch_id=$1 AND document_id=$2`, item.BatchID, item.DocumentID, item.Status, item.OutcomeCode, item.ClearJob, command.RecheckAfter.Seconds()); err != nil {
				return err
			}
		}
		for _, aggregate := range command.Aggregates {
			c := aggregate.Counts
			if _, err := tx.Exec(ctx, `UPDATE document_reindex_batches SET needs_aggregation=false,discovered=$2,waiting=$3,running=$4,succeeded=$5,failed=$6,skipped=$7,superseded=$8,status=$9,finished_at=CASE WHEN $10 THEN COALESCE(finished_at,clock_timestamp()) ELSE finished_at END WHERE id=$1`, aggregate.BatchID, c.Discovered, c.Waiting, c.Running, c.Succeeded, c.Failed, c.Skipped, c.Superseded, aggregate.Status, aggregate.Finished); err != nil {
				return err
			}
		}
		return nil
	})
}
