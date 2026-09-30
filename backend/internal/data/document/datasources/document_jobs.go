package datasources

import (
	"context"
	"strconv"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func documentJobHistoryColumns() string {
	return `j.id,j.document_id,CASE WHEN $2::boolean THEN d.title END,j.generation,j.reason,j.status,j.stage,j.configuration_revision,j.configuration_fingerprint,j.configuration,j.text_source,j.created_at,j.updated_at,j.started_at,j.finished_at,j.failure_code,CASE WHEN j.pipeline='thumbnail' THEN COALESCE(f.sha256=j.source_sha256 AND j.renderer_revision=` + strconv.Itoa(m.ThumbnailRendererRevision) + ` AND j.status<>'superseded' AND j.attempt=(SELECT max(attempt) FROM document_thumbnail_jobs WHERE account_id=j.account_id AND document_id=j.document_id AND source_sha256=j.source_sha256 AND renderer_revision=j.renderer_revision),false) ELSE COALESCE(p.generation=j.generation AND (j.pipeline='ingestion' OR j.attempt=(SELECT max(attempt) FROM document_ai_jobs WHERE account_id=j.account_id AND document_id=j.document_id)),false) END,d.id IS NULL,COALESCE(j.extraction_method,''),COALESCE(j.extraction_engine,''),COALESCE(j.extraction_engine_version,''),j.pipeline,j.attempt,j.pipeline_version,j.renderer_revision,COALESCE(a.invoice_decision,''),COALESCE(a.invoice_decision_reason,''),COALESCE(a.invoice_classification_pass,0),COALESCE(a.invoice_input_characters,0),COALESCE(a.invoice_source_characters,0)`
}

const historyFrom = ` FROM document_pipeline_jobs j LEFT JOIN document_ai_jobs a ON j.pipeline='ai' AND a.id=j.id AND a.account_id=j.account_id LEFT JOIN documents d ON d.account_id=j.account_id AND d.id=j.document_id LEFT JOIN document_processing p ON p.account_id=j.account_id AND p.document_id=j.document_id LEFT JOIN document_files f ON f.account_id=j.account_id AND f.document_id=j.document_id `

func scanHistory(row pgx.Row) (r.DocumentJobHistoryRecord, error) {
	var v r.DocumentJobHistoryRecord
	e := row.Scan(&v.ID, &v.DocumentID, &v.DocumentTitle, &v.Generation, &v.Reason, &v.Status, &v.Stage, &v.ConfigurationRevision, &v.ConfigurationFingerprint, &v.Configuration, &v.TextSource, &v.CreatedAt, &v.UpdatedAt, &v.StartedAt, &v.FinishedAt, &v.FailureCode, &v.IsCurrent, &v.DocumentDeleted, &v.ExtractionMethod, &v.ExtractionEngine, &v.ExtractionEngineVersion, &v.Pipeline, &v.Attempt, &v.PipelineVersion, &v.RendererRevision, &v.InvoiceDecision, &v.InvoiceDecisionReason, &v.InvoiceClassificationPass, &v.InvoiceInputCharacters, &v.InvoiceSourceCharacters)
	return v, e
}
func normalizeProcessingPage(input m.DocumentProcessingPageInput) (m.DocumentProcessingPageInput, error) {
	if input.Limit == 0 {
		input.Limit = 20
	}
	if input.Limit < 1 || input.Limit > 50 || len(input.Cursor) > 4096 {
		return input, m.DocumentValidationError{Message: "invalid processing pagination"}
	}
	if input.DocumentID != "" {
		if e := m.ValidateAccountID(input.DocumentID); e != nil {
			return input, e
		}
	}
	switch input.Status {
	case "", "skipped", "queued", "running", "succeeded", "failed", "superseded", "cancelled":
	default:
		return input, m.DocumentValidationError{Message: "invalid job status"}
	}
	switch input.Pipeline {
	case "", "ingestion", "ai", "thumbnail":
	default:
		return input, m.DocumentValidationError{Message: "invalid pipeline"}
	}
	return input, nil
}
func processingPosition(input m.DocumentProcessingPageInput, op, scope string) (string, *documentPosition, error) {
	fp, e := pagination.Fingerprint(struct {
		Operation, Scope, Status, DocumentID, Pipeline string
		Limit                                          int
		ActiveOnly                                     bool `json:",omitempty"`
	}{op, scope, input.Status, input.DocumentID, input.Pipeline, input.Limit, input.ActiveOnly})
	if e != nil {
		return "", nil, e
	}
	p, e := decodeDocumentPosition(input.Cursor, op, fp, "newest")
	return fp, p, e
}
func (s *DocumentDataSource) JobsRecord(ctx context.Context, a m.DocumentActor, input m.DocumentProcessingPageInput, projection m.DocumentJobProjection) (r.DocumentJobPageRecord, error) {
	out := r.DocumentJobPageRecord{Items: []r.DocumentJobHistoryRecord{}}
	e := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var e error
		input, e = normalizeProcessingPage(input)
		if e != nil {
			return e
		}
		titles := projection.IncludeTitles
		fp, pos, e := processingPosition(input, "document.jobs", "namespace:"+a.AccountID)
		if e != nil {
			return e
		}
		countRows, e := tx.Query(ctx, "SELECT pipeline,status,count(*) FROM document_pipeline_jobs WHERE account_id=$1 AND ($2='' OR document_id=NULLIF($2,'')::uuid) GROUP BY pipeline,status", a.AccountID, input.DocumentID)
		if e != nil {
			return e
		}
		for countRows.Next() {
			var count r.DocumentJobCountRecord
			if e = countRows.Scan(&count.Pipeline, &count.Status, &count.Count); e != nil {
				countRows.Close()
				return e
			}
			out.Counts = append(out.Counts, count)
		}
		e = countRows.Err()
		countRows.Close()
		if e != nil {
			return e
		}
		args := []any{a.AccountID, titles, input.Status, input.DocumentID, input.Limit + 1, input.Pipeline}
		seek := ""
		if input.ActiveOnly {
			seek += " AND j.status IN ('queued','running')"
		}
		if pos != nil {
			seek += " AND (j.created_at,j.id)<($7::timestamptz,$8::uuid)"
			args = append(args, pos.CreatedAt, pos.ID)
		}
		rows, e := tx.Query(ctx, "SELECT "+documentJobHistoryColumns()+historyFrom+` WHERE j.account_id=$1 AND ($3='' OR j.status=$3) AND ($4='' OR j.document_id=NULLIF($4,'')::uuid) AND ($6='' OR j.pipeline=$6)`+seek+` ORDER BY j.created_at DESC,j.id DESC LIMIT $5`, args...)
		if e != nil {
			return e
		}
		defer rows.Close()
		for rows.Next() {
			v, e := scanHistory(rows)
			if e != nil {
				return e
			}
			out.Items = append(out.Items, v)
		}
		if e = rows.Err(); e != nil {
			return e
		}
		if len(out.Items) > input.Limit {
			out.Items = out.Items[:input.Limit]
			last := out.Items[input.Limit-1]
			out.NextCursor, e = encodeDocumentPosition("document.jobs", fp, "newest", documentPosition{ID: last.ID, CreatedAt: last.CreatedAt})
		}
		return e
	})
	return out, e
}
func (s *DocumentDataSource) JobHistoryRecord(ctx context.Context, a m.DocumentActor, id string, projection m.DocumentJobProjection) (r.DocumentJobHistoryRecord, error) {
	var out r.DocumentJobHistoryRecord
	e := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		if e := m.ValidateAccountID(id); e != nil {
			return e
		}
		var e error
		out, e = scanHistory(tx.QueryRow(ctx, "SELECT "+documentJobHistoryColumns()+historyFrom+" WHERE j.account_id=$1 AND j.id=$3", a.AccountID, projection.IncludeTitles, id))
		return e
	})
	return out, e
}

const batchColumns = `id,CASE WHEN account_id IS NULL THEN 'system' ELSE 'namespace' END,reason,status,configuration_revision,configuration_fingerprint,created_at,finished_at,enumeration_complete,discovered,waiting,running,succeeded,failed,skipped,superseded`

func scanBatch(row pgx.Row) (r.DocumentReindexBatchRecord, error) {
	var v r.DocumentReindexBatchRecord
	e := row.Scan(&v.ID, &v.Scope, &v.Reason, &v.Status, &v.ConfigurationRevision, &v.ConfigurationFingerprint, &v.CreatedAt, &v.FinishedAt, &v.EnumerationComplete, &v.Discovered, &v.Waiting, &v.Running, &v.Succeeded, &v.Failed, &v.Skipped, &v.Superseded)
	return v, e
}
func batchScope(a m.DocumentActor, system bool) any {
	if system {
		return nil
	}
	return a.AccountID
}
func (s *DocumentDataSource) BatchesRecord(ctx context.Context, a m.DocumentActor, system bool, input m.DocumentProcessingPageInput) (r.DocumentReindexBatchPageRecord, error) {
	out := r.DocumentReindexBatchPageRecord{Items: []r.DocumentReindexBatchRecord{}}
	e := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var e error
		input, e = normalizeProcessingPage(input)
		if e != nil {
			return e
		}
		scope := "namespace:" + a.AccountID
		if system {
			scope = "system"
		}
		fp, pos, e := processingPosition(input, "document.batches", scope)
		if e != nil {
			return e
		}
		countRows, e := tx.Query(ctx, "SELECT status,count(*) FROM document_reindex_batches WHERE account_id IS NOT DISTINCT FROM $1::uuid GROUP BY status", batchScope(a, system))
		if e != nil {
			return e
		}
		for countRows.Next() {
			var count r.DocumentReindexStatusCountRecord
			if e = countRows.Scan(&count.Status, &count.Count); e != nil {
				countRows.Close()
				return e
			}
			out.Counts = append(out.Counts, count)
		}
		e = countRows.Err()
		countRows.Close()
		if e != nil {
			return e
		}
		args := []any{batchScope(a, system), input.Limit + 1}
		seek := ""
		if input.ActiveOnly {
			seek += " AND status IN ('queued','running','enumerating')"
		}
		if pos != nil {
			seek += " AND (created_at,id)<($3::timestamptz,$4::uuid)"
			args = append(args, pos.CreatedAt, pos.ID)
		}
		rows, e := tx.Query(ctx, "SELECT "+batchColumns+` FROM document_reindex_batches WHERE account_id IS NOT DISTINCT FROM $1::uuid`+seek+` ORDER BY created_at DESC,id DESC LIMIT $2`, args...)
		if e != nil {
			return e
		}
		defer rows.Close()
		for rows.Next() {
			v, e := scanBatch(rows)
			if e != nil {
				return e
			}
			out.Items = append(out.Items, v)
		}
		if e = rows.Err(); e != nil {
			return e
		}
		if len(out.Items) > input.Limit {
			out.Items = out.Items[:input.Limit]
			last := out.Items[input.Limit-1]
			out.NextCursor, e = encodeDocumentPosition("document.batches", fp, "newest", documentPosition{ID: last.ID, CreatedAt: last.CreatedAt})
		}
		return e
	})
	return out, e
}
func (s *DocumentDataSource) BatchRecord(ctx context.Context, a m.DocumentActor, system bool, id string) (r.DocumentReindexBatchRecord, error) {
	var out r.DocumentReindexBatchRecord
	e := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		if e := m.ValidateAccountID(id); e != nil {
			return e
		}
		var e error
		out, e = scanBatch(tx.QueryRow(ctx, "SELECT "+batchColumns+" FROM document_reindex_batches WHERE id=$1 AND account_id IS NOT DISTINCT FROM $2::uuid", id, batchScope(a, system)))
		return e
	})
	return out, e
}
