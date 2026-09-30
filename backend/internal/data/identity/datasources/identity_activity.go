package datasources

import (
	"context"
	"fmt"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const personalActivityUnion = `WITH activity AS (
 SELECT e.id,'email_retrieval'::text AS kind,e.account_id AS namespace_id,a.name AS namespace_name,
 CASE WHEN e.status='superseded' THEN 'cancelled' ELSE e.status END AS status,e.stage,
 e.created_at,e.started_at,e.finished_at,NULL::uuid AS document_id,p.id AS provider_id,NULL::uuid AS batch_id,
 p.label AS title,CASE WHEN e.status='superseded' THEN 'provider_changed' ELSE e.failure_code END AS failure_code,
 p.id IS NOT NULL AS can_open
 FROM email_runs e JOIN accounts a ON a.id=e.account_id
 LEFT JOIN email_providers p ON p.id=e.provider_id AND p.owner_id=e.owner_id AND p.account_id=e.account_id AND p.deleted_at IS NULL
 WHERE e.owner_id=$1 AND e.account_id=ANY($3::uuid[])
 UNION ALL
 SELECT j.id,CASE WHEN j.pipeline='ai' THEN 'document_ai' ELSE 'document_processing' END,j.account_id,a.name,j.status,j.stage,j.created_at,j.started_at,j.finished_at,
 d.id,NULL::uuid,NULL::uuid,d.title,j.failure_code,d.id IS NOT NULL
 FROM document_pipeline_jobs j JOIN accounts a ON a.id=j.account_id
 LEFT JOIN documents d ON d.id=j.document_id AND d.account_id=j.account_id AND d.account_id=ANY($5::uuid[])
 WHERE j.initiated_by_user_id=$1 AND j.parent_batch_id IS NULL AND j.account_id=ANY($2::uuid[])
 UNION ALL
 SELECT b.id,'reindex_batch',b.account_id,a.name,
 CASE b.status WHEN 'enumerating' THEN 'queued' WHEN 'completed_with_failures' THEN 'partial' ELSE b.status END,
 CASE b.status WHEN 'enumerating' THEN 'enumerating' WHEN 'running' THEN 'processing' ELSE 'complete' END,
 b.created_at,NULL::timestamptz,b.finished_at,NULL::uuid,NULL::uuid,b.id,NULL::text,NULL::text,true
 FROM document_reindex_batches b JOIN accounts a ON a.id=b.account_id
 WHERE b.requester_id=$1 AND b.reason='manual' AND b.account_id=ANY($4::uuid[])
) SELECT id,kind,namespace_id,namespace_name,status,stage,created_at,started_at,finished_at,
 document_id,provider_id,batch_id,title,failure_code,can_open FROM activity `

func scanActivity(row pgx.Row) (r.IdentityActivityRecord, error) {
	var item r.IdentityActivityRecord
	err := row.Scan(&item.ID, &item.Kind, &item.NamespaceID, &item.NamespaceName, &item.Status, &item.Stage, &item.CreatedAt, &item.StartedAt, &item.FinishedAt, &item.DocumentID, &item.ProviderID, &item.BatchID, &item.Title, &item.FailureCode, &item.CanOpen)
	return item, err
}

func (source *IdentityDataSource) PersonalActivityRecords(ctx context.Context, actor r.IdentityRecord, page r.IdentityActivityPageRequest) (r.IdentityActivityRecords, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	result := r.IdentityActivityRecords{}
	tx, err := source.database.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return result, fmt.Errorf("begin personal activity snapshot: %w", err)
	}
	defer tx.Rollback(context.Background())
	if err := tx.QueryRow(ctx, "SELECT transaction_timestamp()").Scan(&result.GeneratedAt); err != nil {
		return result, err
	}
	args := []any{actor.User.ID, page.Documents, page.Email, page.Batches, page.Titles}
	result.Active, result.ActiveNextCursor, err = readActivity(ctx, tx, args, actor, false, page.ActiveCursor)
	if err != nil {
		return result, err
	}
	result.ActiveTruncated = result.ActiveNextCursor != ""
	result.Finished, result.FinishedNextCursor, err = readActivity(ctx, tx, args, actor, true, page.FinishedCursor)
	if err != nil {
		return result, err
	}
	if err := tx.Commit(ctx); err != nil {
		return result, fmt.Errorf("finish personal activity snapshot: %w", err)
	}
	return result, nil
}

func (source *IdentityDataSource) IdentityActivityMemberships(ctx context.Context, user uuid.UUID) ([]r.IdentityActivityMembershipRecord, error) {
	tx, err := source.database.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, "SELECT account_id,role,is_owner,claims,enabled FROM memberships WHERE user_id=$1 ORDER BY account_id LIMIT 10001", user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []r.IdentityActivityMembershipRecord{}
	for rows.Next() {
		if len(result) == 10000 {
			return nil, r.ErrActivityUnavailable
		}
		var record r.IdentityActivityMembershipRecord
		if err := rows.Scan(&record.AccountID, &record.Role, &record.Owner, &record.Claims, &record.Enabled); err != nil {
			return nil, err
		}
		result = append(result, record)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	return result, tx.Commit(ctx)
}
