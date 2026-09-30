package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func pageFingerprint(a d.DocumentActor, page m.PaperlessPageRequest, id string) (string, error) {
	if page.Limit < 1 || page.Limit > 100 {
		return "", m.PaperlessFailure{Code: "invalid_pagination"}
	}
	values := []any{a.AccountID, a.UserID, page.Limit, id}
	if page.ActiveOnly {
		values = append(values, "active")
	}
	if page.Status != "" {
		values = append(values, page.Status)
	}
	return pagination.Fingerprint(values)
}

func (s *PaperlessJobsDataSource) List(ctx context.Context, a d.DocumentActor, page m.PaperlessPageRequest) (m.PaperlessRunPage, error) {
	result := m.PaperlessRunPage{Items: []m.PaperlessRun{}}
	err := s.readTx(ctx, a, func(tx pgx.Tx) error {
		fingerprint, err := pageFingerprint(a, page, "")
		if err != nil {
			return err
		}
		var created *time.Time
		var id *uuid.UUID
		if page.Cursor != "" {
			key, err := pagination.Decode(page.Cursor, "paperless-runs", fingerprint, "created_desc")
			if err != nil || len(key) != 2 || json.Unmarshal(key["created"], &created) != nil || created == nil || created.IsZero() || json.Unmarshal(key["id"], &id) != nil || id == nil || *id == uuid.Nil {
				return m.PaperlessFailure{Code: "invalid_pagination"}
			}
		}
		countRows, err := tx.Query(ctx, "SELECT CASE WHEN state=$3 AND EXISTS (SELECT 1 FROM paperless_items WHERE run_id=r.id AND status=$4) THEN $5 ELSE state END AS status,count(*) FROM paperless_runs r WHERE account_id=$1 AND owner_id=$2 GROUP BY 1", a.AccountID, a.UserID, page.Projection.Completed, page.Projection.FailedItem, page.Projection.Partial)
		if err != nil {
			return err
		}
		for countRows.Next() {
			var count m.PaperlessJobStatusCount
			if err = countRows.Scan(&count.Status, &count.Count); err != nil {
				countRows.Close()
				return err
			}
			result.Counts = append(result.Counts, count)
		}
		err = countRows.Err()
		countRows.Close()
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT id FROM paperless_runs r WHERE account_id=$1 AND owner_id=$2
AND (NOT $10 OR state IN ('queued','running'))
AND ($6='' OR CASE WHEN state=$7 AND EXISTS (SELECT 1 FROM paperless_items WHERE run_id=r.id AND status=$8) THEN $9 ELSE state END=$6)
AND ($3::timestamptz IS NULL OR (created_at,id)<($3,$4::uuid)) ORDER BY created_at DESC,id DESC LIMIT $5`, a.AccountID, a.UserID, created, id, page.Limit+1, page.Status, page.Projection.Completed, page.Projection.FailedItem, page.Projection.Partial, page.ActiveOnly)
		if err != nil {
			return err
		}
		var ids []string
		for rows.Next() {
			var value string
			if err = rows.Scan(&value); err != nil {
				rows.Close()
				return err
			}
			ids = append(ids, value)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		more := len(ids) > page.Limit
		if more {
			ids = ids[:page.Limit]
		}
		for _, value := range ids {
			run, err := readRun(ctx, tx, value, false)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, run)
		}
		if more {
			last := result.Items[len(result.Items)-1]
			result.NextCursor, err = pagination.Encode("paperless-runs", fingerprint, "created_desc", map[string]any{"created": last.CreatedAt, "id": last.ID})
		}
		return err
	})
	return result, err
}

func (s *PaperlessJobsDataSource) Outcomes(ctx context.Context, a d.DocumentActor, id string, page m.PaperlessPageRequest) (m.PaperlessOutcomePage, error) {
	result := m.PaperlessOutcomePage{Items: []m.PaperlessOutcome{}}
	switch page.Status {
	case "", "imported", "duplicate", "failed":
	default:
		return result, m.PaperlessFailure{Code: "invalid_pagination"}
	}
	err := s.readTx(ctx, a, func(tx pgx.Tx) error {
		var owned string
		if err := tx.QueryRow(ctx, "SELECT id FROM paperless_runs WHERE id=$1 AND account_id=$2 AND owner_id=$3", id, a.AccountID, a.UserID).Scan(&owned); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return d.ErrNotFound
			}
			return err
		}
		fingerprint, err := pageFingerprint(a, page, id)
		if err != nil {
			return err
		}
		var before *int64
		if page.Cursor != "" {
			key, err := pagination.Decode(page.Cursor, "paperless-outcomes", fingerprint, "source_desc")
			if err != nil || len(key) != 1 || json.Unmarshal(key["source"], &before) != nil || before == nil || *before < 1 {
				return m.PaperlessFailure{Code: "invalid_pagination"}
			}
		}
		rows, err := tx.Query(ctx, "SELECT source_id,title,status,failure_code,COALESCE(document_id::text,'') FROM paperless_items WHERE run_id=$1 AND status<>'pending' AND ($4='' OR status=$4) AND ($2::bigint IS NULL OR source_id<$2) ORDER BY source_id DESC LIMIT $3", id, before, page.Limit+1, page.Status)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var outcome m.PaperlessOutcome
			if err = rows.Scan(&outcome.SourceID, &outcome.Title, &outcome.Status, &outcome.FailureCode, &outcome.DocumentID); err != nil {
				return err
			}
			result.Items = append(result.Items, outcome)
		}
		if err = rows.Err(); err != nil {
			return err
		}
		if len(result.Items) > page.Limit {
			result.Items = result.Items[:page.Limit]
			result.NextCursor, err = pagination.Encode("paperless-outcomes", fingerprint, "source_desc", map[string]any{"source": result.Items[page.Limit-1].SourceID})
		}
		return err
	})
	return result, err
}
