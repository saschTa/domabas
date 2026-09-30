package datasources

import (
	"context"
	"encoding/json"
	"fmt"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/model"
	"github.com/domabas/domabas/backend/internal/data/postgres/generated/table"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	jet "github.com/go-jet/jet/v2/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const documentColumns = `d.id,d.title,d.description,d.created_at,d.kind,d.tags,d.sender,d.recipients,d.cc,d.bcc,COALESCE(d.document_date::text,''),d.subject,d.message_id,
 CASE WHEN f.document_id IS NULL THEN NULL ELSE jsonb_build_object('OriginalFilename',f.original_filename,'MediaType',f.media_type,'Size',f.size,'SHA256',f.sha256,'IngestedAt',f.ingested_at,'UploaderID',f.uploader_id) END,
 CASE WHEN p.document_id IS NULL THEN NULL ELSE jsonb_build_object('State',p.state,'Stage',p.stage,'Generation',p.generation,'ConfigurationRevision',p.configuration_revision,'UpdatedAt',p.updated_at,'FailureCode',COALESCE(p.failure_code,''),'Configuration',p.configuration,'ExtractionMethod',COALESCE(p.extraction_method,''),'ExtractionEngine',COALESCE(p.extraction_engine,''),'ExtractionEngineVersion',COALESCE(p.extraction_engine_version,'')) END,COALESCE(ai.id::text,''),COALESCE(ai.status,''),COALESCE(ai.stage,''),COALESCE(ai.attempt,0),COALESCE(ai.configuration_revision,0),ai.failure_code,COALESCE(ai.updated_at,p.updated_at,d.created_at),ai.started_at,ai.finished_at,COALESCE(t.source_sha256,''),COALESCE(t.sha256,''),COALESCE(t.media_type,''),COALESCE(t.size,0),COALESCE(t.width,0),COALESCE(t.height,0),COALESCE(t.renderer_revision,0)`
const documentFrom = ` FROM documents d LEFT JOIN document_files f ON f.document_id=d.id AND f.account_id=d.account_id LEFT JOIN document_processing p ON p.document_id=d.id AND p.account_id=d.account_id LEFT JOIN LATERAL(SELECT id,status,stage,attempt,configuration_revision,failure_code,updated_at,started_at,finished_at FROM document_ai_jobs WHERE account_id=d.account_id AND document_id=d.id AND generation=p.generation ORDER BY attempt DESC LIMIT 1) ai ON true LEFT JOIN document_thumbnails t ON t.account_id=d.account_id AND t.document_id=d.id AND t.source_sha256=f.sha256 AND t.renderer_revision=1 `

func scanDocument(row pgx.Row) (r.DocumentRecord, error) {
	var d r.DocumentRecord
	var file, processing []byte
	var ai r.DocumentAIProcessingRecord
	var thumbnail r.DocumentThumbnailRecord
	err := row.Scan(&d.ID, &d.Title, &d.Description, &d.CreatedAt, &d.Kind, &d.Tags, &d.Sender, &d.Recipients, &d.CC, &d.BCC, &d.DocumentDate, &d.Subject, &d.MessageID, &file, &processing, &ai.JobID, &ai.Status, &ai.Stage, &ai.Attempt, &ai.ConfigurationRevision, &ai.FailureCode, &ai.UpdatedAt, &ai.StartedAt, &ai.FinishedAt, &thumbnail.SourceSHA256, &thumbnail.SHA256, &thumbnail.MediaType, &thumbnail.Size, &thumbnail.Width, &thumbnail.Height, &thumbnail.RendererRevision)
	if err != nil {
		return d, err
	}
	if thumbnail.SHA256 != "" {
		d.Thumbnail = &thumbnail
	}
	d.CreatedAt = d.CreatedAt.UTC()
	if len(file) > 0 {
		if err = json.Unmarshal(file, &d.File); err != nil {
			return d, err
		}
	}
	if len(processing) > 0 {
		err = json.Unmarshal(processing, &d.Processing)
		if err == nil && ai.JobID != "" {
			d.Processing.AI = &ai
		}
	}
	return d, err
}
func readDocument(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, account, id string) (r.DocumentRecord, error) {
	return scanDocument(q.QueryRow(ctx, "SELECT "+documentColumns+documentFrom+"WHERE d.account_id=$1 AND d.id=$2", account, id))
}
func (source *DocumentDataSource) CreateDocument(ctx context.Context, record model.Documents) (r.DocumentRecord, error) {
	var result r.DocumentRecord
	err := pgx.BeginFunc(ctx, source.database, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		if err := coordinateDocumentPublication(ctx, tx); err != nil {
			return err
		}
		documents := table.Documents.FromSchema("")
		query, args := documents.INSERT(documents.ID, documents.AccountID, documents.Title, documents.Description, documents.CreatedAt).MODEL(record).RETURNING(documents.ID).Sql()
		var id string
		if err := tx.QueryRow(ctx, query, args...).Scan(&id); err != nil {
			return err
		}
		var err error
		result, err = readDocument(ctx, tx, record.AccountID.String(), id)
		return err
	})
	return result, documentError(err)
}
func (source *DocumentDataSource) GetDocument(ctx context.Context, accountID, id string) (r.DocumentRecord, error) {
	if _, err := uuid.Parse(accountID); err != nil {
		return r.DocumentRecord{}, fmt.Errorf("parse account ID: %w", err)
	}
	if _, err := uuid.Parse(id); err != nil {
		return r.DocumentRecord{}, fmt.Errorf("parse document ID: %w", err)
	}
	return readDocument(ctx, source.database, accountID, id)
}
func (source *DocumentDataSource) ListDocuments(ctx context.Context, accountID string, limit, offset int, cursor string) (r.DocumentRecords, error) {
	account, err := uuid.Parse(accountID)
	if err != nil {
		return r.DocumentRecords{}, fmt.Errorf("parse account ID: %w", err)
	}
	result := r.DocumentRecords{Items: []r.DocumentRecord{}}
	if err := (m.DocumentPageRequest{Limit: limit, Offset: offset, Cursor: cursor}).Validate(); err != nil {
		return result, err
	}
	fingerprint, err := documentCursorFingerprint(accountID, "documents.browse", m.DocumentSearchInput{Limit: limit, Sort: "newest"})
	if err != nil {
		return result, err
	}
	position, err := decodeDocumentPosition(cursor, "documents.browse", fingerprint, "newest")
	if err != nil {
		return result, err
	}
	documents := table.Documents.FromSchema("")
	err = pgx.BeginTxFunc(ctx, source.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		query, args := jet.SELECT(jet.COUNT(documents.ID)).FROM(documents).WHERE(documents.AccountID.EQ(jet.UUID(account))).Sql()
		if err := tx.QueryRow(ctx, query, args...).Scan(&result.Total); err != nil {
			return err
		}
		pageArgs := []any{accountID, limit + 1, offset}
		seek := ""
		if position != nil {
			seek = " AND (d.created_at,d.id) < ($4::timestamptz,$5::uuid)"
			pageArgs = append(pageArgs, position.CreatedAt, position.ID)
		}
		rows, err := tx.Query(ctx, "SELECT "+documentColumns+documentFrom+"WHERE d.account_id=$1"+seek+" ORDER BY d.created_at DESC,d.id DESC LIMIT $2 OFFSET $3", pageArgs...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			record, err := scanDocument(rows)
			if err != nil {
				return err
			}
			result.Items = append(result.Items, record)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		if len(result.Items) > limit {
			result.Items = result.Items[:limit]
			last := result.Items[limit-1]
			result.NextCursor, err = encodeDocumentPosition("documents.browse", fingerprint, "newest", documentPosition{ID: last.ID, CreatedAt: last.CreatedAt})
			return err
		}
		return nil
	})
	return result, err
}
