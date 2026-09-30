package datasources

import (
	"context"
	"errors"
	"fmt"
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"time"
)

const thumbnailEligible = `f.media_type IN ('application/pdf','image/png','image/jpeg') AND p.state='ready'`
const thumbnailMissing = `NOT EXISTS(SELECT 1 FROM document_thumbnails t WHERE t.account_id=f.account_id AND t.document_id=f.document_id AND t.source_sha256=f.sha256 AND t.renderer_revision=$1) AND NOT EXISTS(SELECT 1 FROM document_thumbnail_jobs j WHERE j.account_id=f.account_id AND j.document_id=f.document_id AND j.source_sha256=f.sha256 AND j.renderer_revision=$1)`

func (s *DocumentDataSource) DiscoverThumbnails(ctx context.Context) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		var cursorAccount, cursorDocument, upperAccount, upperDocument *string
		err := tx.QueryRow(ctx, `SELECT cursor_account::text,cursor_document::text,upper_account::text,upper_document::text FROM document_thumbnail_scan WHERE singleton AND next_scan_at<=clock_timestamp() FOR UPDATE SKIP LOCKED`).Scan(&cursorAccount, &cursorDocument, &upperAccount, &upperDocument)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if upperAccount == nil {
			err = tx.QueryRow(ctx, `SELECT f.account_id::text,f.document_id::text FROM document_files f JOIN document_processing p USING(account_id,document_id) WHERE `+thumbnailEligible+` ORDER BY f.account_id DESC,f.document_id DESC LIMIT 1`).Scan(&upperAccount, &upperDocument)
			if err != nil && !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
		}
		rows, err := tx.Query(ctx, `SELECT f.account_id::text,f.document_id::text,f.sha256 FROM document_files f JOIN document_processing p USING(account_id,document_id) WHERE `+thumbnailEligible+` AND `+thumbnailMissing+` AND ($2::uuid IS NULL OR (f.account_id,f.document_id)>($2::uuid,$3::uuid)) AND (f.account_id,f.document_id)<=($4::uuid,$5::uuid) ORDER BY f.account_id,f.document_id LIMIT 100`, m.ThumbnailRendererRevision, cursorAccount, cursorDocument, upperAccount, upperDocument)
		if err != nil {
			return err
		}
		var jobs []r.DocumentThumbnailJobRecord
		for rows.Next() {
			var j r.DocumentThumbnailJobRecord
			if err = rows.Scan(&j.AccountID, &j.DocumentID, &j.SourceSHA256); err != nil {
				rows.Close()
				return err
			}
			jobs = append(jobs, j)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		for _, j := range jobs {
			id := uuid.NewString()
			if _, err = tx.Exec(ctx, `INSERT INTO document_thumbnail_jobs(id,account_id,document_id,source_sha256,renderer_revision,workflow_id) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING`, id, j.AccountID, j.DocumentID, j.SourceSHA256, m.ThumbnailRendererRevision, "document-thumbnail-v1/"+id); err != nil {
				return err
			}
		}
		if len(jobs) == 100 {
			last := jobs[len(jobs)-1]
			cursorAccount, cursorDocument = &last.AccountID, &last.DocumentID
		} else {
			cursorAccount, cursorDocument, upperAccount, upperDocument = nil, nil, nil, nil
		}
		_, err = tx.Exec(ctx, `UPDATE document_thumbnail_scan SET next_scan_at=clock_timestamp()+interval '1 minute',cursor_account=$1,cursor_document=$2,upper_account=$3,upper_document=$4 WHERE singleton`, cursorAccount, cursorDocument, upperAccount, upperDocument)
		return err
	})
}

const thumbnailJobColumns = `id::text,account_id::text,document_id::text,source_sha256,renderer_revision,attempt,workflow_id,run_id,task_queue,COALESCE(lease_token::text,''),status,COALESCE(permit_end,'epoch'::timestamptz),COALESCE(admitted_at,'epoch'::timestamptz)`

func (s *DocumentDataSource) ClaimThumbnailRecords(ctx context.Context, queue string) ([]r.DocumentThumbnailJobRecord, error) {
	jobs := []r.DocumentThumbnailJobRecord{}
	if queue == "" || s.scheduler == nil {
		return jobs, errors.New("thumbnail scheduler and queue are required")
	}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+thumbnailJobColumns+` FROM document_thumbnail_jobs WHERE status='queued' AND available_at<=clock_timestamp() AND (lease_until IS NULL OR lease_until<=clock_timestamp()) AND run_id='' AND closed_at IS NULL AND (admitted_at IS NULL OR admitted_at>clock_timestamp()-interval '30 minutes') ORDER BY available_at,created_at,id LIMIT 20 FOR UPDATE SKIP LOCKED`)
		if err != nil {
			return err
		}
		var candidates []r.DocumentThumbnailJobRecord
		for rows.Next() {
			j, e := thumbnailJobMapper(rows)
			if e != nil {
				rows.Close()
				return e
			}
			candidates = append(candidates, j)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		for _, j := range candidates {
			var eligible bool
			if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM document_files f WHERE f.account_id=$1 AND f.document_id=$2 AND f.sha256=$3 AND f.media_type IN ('application/pdf','image/png','image/jpeg'))`, j.AccountID, j.DocumentID, j.SourceSHA256).Scan(&eligible); err != nil {
				return err
			}
			if !eligible && j.AdmittedAt.Equal(time.Unix(0, 0)) {
				if _, err = tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET status='obsolete',closed_at=clock_timestamp() WHERE id=$1`, j.ID); err != nil {
					return err
				}
				continue
			}
			reserved, e := s.scheduler.Reserve(ctx, tx, j.WorkflowID, "document_thumbnail", nil)
			if e != nil {
				return e
			}
			if !reserved {
				continue
			}
			j, e = thumbnailJobMapper(tx.QueryRow(ctx, `UPDATE document_thumbnail_jobs SET admitted_at=COALESCE(admitted_at,clock_timestamp()),task_queue=CASE WHEN task_queue='' THEN $2 ELSE task_queue END,lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '30 seconds',permit_end=clock_timestamp()+interval '10 seconds',next_check_at=clock_timestamp()+interval '30 seconds' WHERE id=$1 RETURNING `+thumbnailJobColumns, j.ID, queue))
			if e != nil {
				return e
			}
			jobs = append(jobs, j)
			break
		}
		return nil
	})
	return jobs, err
}
func (s *DocumentDataSource) AcknowledgeThumbnail(ctx context.Context, j m.DocumentThumbnailJob, run string) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET run_id=$3,lease_until=NULL,status=CASE WHEN status='queued' THEN 'running' ELSE status END,next_check_at=clock_timestamp()+interval '15 seconds' WHERE id=$1 AND lease_token=$2 AND (run_id='' OR run_id=$3) AND closed_at IS NULL`, j.ID, j.LeaseToken, run)
		return err
	})
}
func (s *DocumentDataSource) ReleaseThumbnail(ctx context.Context, j m.DocumentThumbnailJob) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET lease_until=clock_timestamp()+interval '5 seconds',next_check_at=clock_timestamp() WHERE id=$1 AND lease_token=$2 AND run_id='' AND closed_at IS NULL`, j.ID, j.LeaseToken)
		return err
	})
}
func (s *DocumentDataSource) PendingThumbnailRecords(ctx context.Context) ([]r.DocumentThumbnailJobRecord, error) {
	result := []r.DocumentThumbnailJobRecord{}
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `UPDATE document_thumbnail_jobs SET next_check_at=clock_timestamp()+interval '15 seconds' WHERE id IN (SELECT id FROM document_thumbnail_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL AND next_check_at<=clock_timestamp() ORDER BY next_check_at,id LIMIT 20 FOR UPDATE SKIP LOCKED) RETURNING `+thumbnailJobColumns)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			j, e := thumbnailJobMapper(rows)
			if e != nil {
				return e
			}
			result = append(result, j)
		}
		return rows.Err()
	})
	return result, err
}
func (s *DocumentDataSource) ResolveThumbnail(ctx context.Context, j m.DocumentThumbnailJob, run string, closed, missing bool, retryDelay time.Duration) error {
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		current, err := thumbnailJobMapper(tx.QueryRow(ctx, `SELECT `+thumbnailJobColumns+` FROM document_thumbnail_jobs WHERE id=$1 AND closed_at IS NULL FOR UPDATE`, j.ID))
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if current.RunID != "" && run != "" && current.RunID != run {
			return m.ErrStaleJob
		}
		if missing {
			var safe bool
			if err = tx.QueryRow(ctx, `SELECT run_id='' AND admitted_at>clock_timestamp()-interval '1 hour' AND permit_end<clock_timestamp()-interval '15 minutes' AND (lease_until IS NULL OR lease_until<clock_timestamp()) FROM document_thumbnail_jobs WHERE id=$1`, j.ID).Scan(&safe); err != nil {
				return err
			}
			if !safe {
				return nil
			}
			closed = true
		}
		if !closed {
			if run != "" {
				_, err = tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET run_id=$2,status=CASE WHEN status='queued' THEN 'running' ELSE status END WHERE id=$1`, j.ID, run)
			}
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET closed_at=clock_timestamp(),run_id=CASE WHEN $2='' THEN run_id ELSE $2 END,retryable=CASE WHEN status IN ('queued','running') THEN true ELSE retryable END,failure_code=CASE WHEN status IN ('queued','running') THEN 'execution_incomplete' ELSE failure_code END,status=CASE WHEN status IN ('queued','running') THEN 'failed' ELSE status END WHERE id=$1`, j.ID, run); err != nil {
			return err
		}
		id := uuid.NewString()
		_, err = tx.Exec(ctx, `INSERT INTO document_thumbnail_jobs(id,account_id,document_id,source_sha256,renderer_revision,attempt,workflow_id,available_at) SELECT $2,j.account_id,j.document_id,j.source_sha256,j.renderer_revision,j.attempt+1,$3,clock_timestamp()+$4::double precision*interval '1 second' FROM document_thumbnail_jobs j JOIN document_files f USING(account_id,document_id) WHERE j.id=$1 AND j.status='failed' AND j.retryable AND j.source_sha256=f.sha256 AND NOT EXISTS(SELECT 1 FROM document_thumbnails t WHERE t.account_id=j.account_id AND t.document_id=j.document_id AND t.source_sha256=j.source_sha256 AND t.renderer_revision=j.renderer_revision) ON CONFLICT DO NOTHING`, j.ID, id, "document-thumbnail-v1/"+id, retryDelay.Seconds())
		return err
	})
}
func (s *DocumentDataSource) ThumbnailWorkRecord(ctx context.Context, j m.DocumentThumbnailJob) (r.DocumentThumbnailWorkRecord, error) {
	var result r.DocumentThumbnailWorkRecord
	err := pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		var status string
		if err := tx.QueryRow(ctx, `SELECT status FROM document_thumbnail_jobs WHERE id=$1 AND account_id=$2 AND document_id=$3 AND source_sha256=$4 AND renderer_revision=$5 AND admitted_at IS NOT NULL AND closed_at IS NULL`, j.ID, j.AccountID, j.DocumentID, j.SourceSHA256, j.RendererRevision).Scan(&status); err != nil {
			return staleError(err)
		}
		if status == "succeeded" {
			result.Complete = true
			return nil
		}
		if status != "queued" && status != "running" {
			return m.ErrStaleJob
		}
		ref, err := fileReference(ctx, tx, j.AccountID, j.DocumentID)
		if err != nil {
			return staleError(err)
		}
		if ref.File.SHA256 != j.SourceSHA256 || j.RendererRevision != m.ThumbnailRendererRevision {
			return m.ErrStaleJob
		}
		result.Reference = ref
		_, err = tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET status='running' WHERE id=$1 AND status='queued'`, j.ID)
		return err
	})
	return result, err
}
func (s *DocumentDataSource) PublishThumbnail(ctx context.Context, j m.DocumentThumbnailJob, c m.DocumentThumbnailContent) error {
	if j.RendererRevision != m.ThumbnailRendererRevision {
		return m.ErrStaleJob
	}
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		if err := lockDocument(ctx, tx, j.AccountID, j.DocumentID); err != nil {
			return staleError(err)
		}
		var source string
		if err := tx.QueryRow(ctx, `SELECT sha256 FROM document_files WHERE account_id=$1 AND document_id=$2 FOR UPDATE`, j.AccountID, j.DocumentID).Scan(&source); err != nil {
			return staleError(err)
		}
		if source != j.SourceSHA256 {
			return m.ErrStaleJob
		}
		var status string
		if err := tx.QueryRow(ctx, `SELECT status FROM document_thumbnail_jobs WHERE id=$1 AND account_id=$2 AND document_id=$3 AND source_sha256=$4 AND renderer_revision=$5 AND closed_at IS NULL FOR UPDATE`, j.ID, j.AccountID, j.DocumentID, j.SourceSHA256, j.RendererRevision).Scan(&status); err != nil {
			return staleError(err)
		}
		if status == "succeeded" {
			return nil
		}
		if status != "running" || c.Descriptor.SourceSHA256 != source || c.Descriptor.RendererRevision != j.RendererRevision {
			return m.ErrStaleJob
		}
		d := c.Descriptor
		if _, err := tx.Exec(ctx, `INSERT INTO document_thumbnails(account_id,document_id,source_sha256,renderer_revision,sha256,media_type,width,height,size,content) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(account_id,document_id) DO UPDATE SET source_sha256=EXCLUDED.source_sha256,renderer_revision=EXCLUDED.renderer_revision,sha256=EXCLUDED.sha256,media_type=EXCLUDED.media_type,width=EXCLUDED.width,height=EXCLUDED.height,size=EXCLUDED.size,content=EXCLUDED.content,created_at=clock_timestamp()`, j.AccountID, j.DocumentID, d.SourceSHA256, d.RendererRevision, d.SHA256, d.MediaType, d.Width, d.Height, d.Size, c.Bytes); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET status='succeeded',retryable=false,failure_code='' WHERE id=$1`, j.ID)
		return err
	})
}
func (s *DocumentDataSource) FinishThumbnail(ctx context.Context, j m.DocumentThumbnailJob, outcome m.DocumentThumbnailOutcome) error {
	status := outcome.Status
	return pgx.BeginFunc(ctx, s.database, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE document_thumbnail_jobs SET status=$2,retryable=$3,failure_code=$4 WHERE id=$1 AND status IN ('queued','running') AND closed_at IS NULL`, j.ID, status, outcome.Retryable, outcome.FailureCode)
		return err
	})
}
func (s *DocumentDataSource) ReadThumbnailRecord(ctx context.Context, a m.DocumentActor, id, expected string) (r.DocumentThumbnailContentRecord, error) {
	var result r.DocumentThumbnailContentRecord
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		d := &result.Descriptor
		return tx.QueryRow(ctx, `SELECT t.source_sha256,t.sha256,t.media_type,t.size,t.width,t.height,t.renderer_revision,t.content FROM document_thumbnails t JOIN document_files f USING(account_id,document_id) WHERE t.account_id=$1 AND t.document_id=$2 AND t.sha256=$3 AND t.source_sha256=f.sha256 AND t.renderer_revision=$4`, a.AccountID, id, expected, m.ThumbnailRendererRevision).Scan(&d.SourceSHA256, &d.SHA256, &d.MediaType, &d.Size, &d.Width, &d.Height, &d.RendererRevision, &result.Bytes)
	})
	if err != nil {
		return result, fmt.Errorf("read document thumbnail: %w", err)
	}
	return result, nil
}
