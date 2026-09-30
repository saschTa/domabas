package datasources

import (
	"context"
	"github.com/jackc/pgx/v5"
)

const schedulerClosedExecution = `(
 (q.pipeline='document_thumbnail' AND EXISTS(SELECT 1 FROM document_thumbnail_jobs t WHERE t.workflow_id=q.workflow_id AND t.closed_at IS NOT NULL))
 OR (q.pipeline='document_ingestion' AND EXISTS(SELECT 1 FROM document_processing_executions e WHERE e.workflow_id=q.workflow_id AND e.closed_at IS NOT NULL))
 OR (q.pipeline='document_ai' AND EXISTS(SELECT 1 FROM document_ai_jobs a WHERE a.workflow_id=q.workflow_id AND a.closed_at IS NOT NULL))
 OR (q.pipeline='email' AND EXISTS(SELECT 1 FROM email_executions e WHERE e.workflow_id=q.workflow_id AND e.closed_at IS NOT NULL))
 OR (q.pipeline='paperless' AND EXISTS(SELECT 1 FROM paperless_runs p WHERE 'domabas-paperless-'||p.id::text=q.workflow_id AND p.execution_closed))
 OR (q.pipeline='chat' AND EXISTS(SELECT 1 FROM chat_turns c WHERE c.workflow_id=q.workflow_id AND c.execution_closed))
)`

func reconcileScheduler(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `UPDATE scheduler_requests q SET state='released',released_at=clock_timestamp() WHERE q.state='active' AND `+schedulerClosedExecution)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `DELETE FROM scheduler_requests q WHERE q.state='waiting' AND NOT (
 (q.pipeline='document_thumbnail' AND EXISTS(SELECT 1 FROM document_thumbnail_jobs t WHERE t.workflow_id=q.workflow_id AND t.status IN ('queued','running') AND t.closed_at IS NULL))
 OR (q.pipeline='document_ingestion' AND EXISTS(SELECT 1 FROM document_processing p WHERE (CASE WHEN p.split_pipeline THEN 'document-ingestion-v2/' ELSE 'document-ingestion-v1/' END)||p.account_id::text||'/'||p.document_id::text||'/'||p.generation::text=q.workflow_id AND p.state IN ('queued','processing')))
 OR (q.pipeline='document_ai' AND EXISTS(SELECT 1 FROM document_ai_jobs a WHERE 'document-ai-v1/'||a.account_id::text||'/'||a.document_id::text||'/'||a.generation::text||'/'||a.attempt::text=q.workflow_id AND a.status IN ('queued','running') AND a.closed_at IS NULL))
 OR (q.pipeline='email' AND EXISTS(SELECT 1 FROM email_runs e WHERE 'domabas-email-'||e.id::text=q.workflow_id AND e.status IN ('queued','running')))
 OR (q.pipeline='paperless' AND EXISTS(SELECT 1 FROM paperless_runs p WHERE 'domabas-paperless-'||p.id::text=q.workflow_id AND p.state IN ('queued','running') AND NOT p.cancel_requested AND NOT p.execution_closed))
 OR (q.pipeline='chat' AND EXISTS(SELECT 1 FROM chat_turns c WHERE c.workflow_id=q.workflow_id AND c.status IN ('queued','running') AND NOT c.execution_closed))
)`)
	return err
}
