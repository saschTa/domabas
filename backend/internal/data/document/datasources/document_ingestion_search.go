package datasources

import (
	"context"
	"encoding/json"
	"fmt"
	"math"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

const searchMetadataEligibility = `d.account_id=$1 AND d.tags @> $2::text[]
 AND (cardinality($8::text[])=0 OR d.kind=ANY($8::text[]))
 AND ($3::text='' OR CASE WHEN $6::text='exact'
 THEN lower(d.sender COLLATE pg_catalog.pg_unicode_fast)=lower($3::text COLLATE pg_catalog.pg_unicode_fast)
 ELSE strpos(lower(d.sender COLLATE pg_catalog.pg_unicode_fast),lower($3::text COLLATE pg_catalog.pg_unicode_fast))>0 END)
 AND ($4::text='' OR EXISTS(SELECT 1 FROM unnest(d.recipients || d.cc || d.bcc) recipient(value)
 WHERE CASE WHEN $7::text='exact'
 THEN lower(recipient.value COLLATE pg_catalog.pg_unicode_fast)=lower($4::text COLLATE pg_catalog.pg_unicode_fast)
 ELSE strpos(lower(recipient.value COLLATE pg_catalog.pg_unicode_fast),lower($4::text COLLATE pg_catalog.pg_unicode_fast))>0 END))`

const eligibleChunks = ` FROM document_chunks c
 JOIN document_processing p ON p.account_id=c.account_id AND p.document_id=c.document_id AND p.generation=c.generation
 JOIN documents d ON d.account_id=c.account_id AND d.id=c.document_id
 WHERE ` + searchMetadataEligibility + ` AND p.state='ready' AND p.ocr_revision=d.ocr_revision
 AND c.embedding IS NOT NULL AND c.model_digest=($5::jsonb->>'Digest') AND p.configuration->>'EmbeddingModel'=($5::jsonb->>'Model') AND p.configuration->>'EmbeddingDigest'=($5::jsonb->>'Digest') AND (p.configuration->>'Dimensions')::integer=($5::jsonb->>'Dimensions')::integer AND p.configuration->>'EmbeddingInputRevision'=($5::jsonb->>'EmbeddingInputRevision') AND p.configuration->>'IndexingRevision'=($5::jsonb->>'IndexingRevision') `

const rankedDocumentColumns = `d.id,d.title,d.kind,d.tags,d.created_at,
 COALESCE(d.document_date::text,'') AS document_date,COALESCE(p.state,'') AS state,
 lower(d.title COLLATE pg_catalog.pg_unicode_fast) AS lower_title,d.document_date AS sort_date`

const fulltextSearch = `WITH terms AS(SELECT websearch_to_tsquery('simple',$5) AS query),
 eligible AS(SELECT d.* FROM documents d WHERE ` + searchMetadataEligibility + `),
 content_hits AS(SELECT c.document_id,max(ts_rank_cd(c.content_vector,terms.query))::float8 AS score,
 (array_agg(left(c.content,512) ORDER BY ts_rank_cd(c.content_vector,terms.query) DESC,c.position))[1] AS snippet
 FROM document_chunks c JOIN document_processing p ON p.account_id=c.account_id AND p.document_id=c.document_id AND p.generation=c.generation
 JOIN eligible d ON d.account_id=c.account_id AND d.id=c.document_id CROSS JOIN terms
 WHERE c.content_vector @@ terms.query GROUP BY c.document_id),
 ranked AS(SELECT ` + rankedDocumentColumns + `,
 (ts_rank_cd(d.metadata_vector,terms.query)::float8+COALESCE(h.score,0)) AS score,
 COALESCE(h.snippet,left(concat_ws(' ',d.title,d.description,d.subject,d.sender),512)) AS snippet
 FROM eligible d CROSS JOIN terms LEFT JOIN content_hits h ON h.document_id=d.id
 LEFT JOIN document_processing p ON p.document_id=d.id AND p.account_id=d.account_id
 WHERE $5::text='' OR d.metadata_vector @@ terms.query OR h.document_id IS NOT NULL) `

const documentVectorDistance = `c.embedding::public.vector(768) OPERATOR(public.<=>) $9::float8[]::public.vector(768)`
const documentSearchTransactionSettings = "SET LOCAL statement_timeout='10s'; SET LOCAL plan_cache_mode=force_custom_plan"
const documentVectorSearchSettings = "SET LOCAL hnsw.ef_search=200; SET LOCAL hnsw.iterative_scan=relaxed_order"

func documentSemanticScores(indexed bool) string {
	query := ""
	if indexed {
		query = `nearest_chunks AS MATERIALIZED(SELECT c.document_id ` + eligibleChunks +
			` ORDER BY ` + documentVectorDistance + ` LIMIT 400), `
	}
	query += `semantic_scores AS(SELECT c.document_id,c.position,left(c.content,512) AS snippet,
 1-(` + documentVectorDistance + `) AS score ` + eligibleChunks
	if indexed {
		query += ` AND c.document_id IN(SELECT document_id FROM nearest_chunks)`
	}
	return query + `), `
}

func documentSemanticSearch(indexed bool) string {
	return `WITH ` + documentSemanticScores(indexed) + `
 best AS(SELECT DISTINCT ON(document_id) document_id,score,snippet
 FROM semantic_scores ORDER BY document_id,score DESC,position),
 ranked AS(SELECT ` + rankedDocumentColumns + `,b.score,b.snippet FROM best b
 JOIN documents d ON d.id=b.document_id AND d.account_id=$1
 JOIN document_processing p ON p.document_id=d.id AND p.account_id=d.account_id) `
}

func (s *DocumentDataSource) SearchRecord(ctx context.Context, a m.DocumentActor, input m.DocumentSearchInput, vector []float64) (r.DocumentSearchRecord, error) {
	result := r.DocumentSearchRecord{Items: []r.DocumentSearchItemRecord{}}
	input, err := input.Normalize()
	if err != nil {
		return result, err
	}
	fingerprint, err := documentCursorFingerprint(a.AccountID, "documents.search", input)
	if err != nil {
		return result, err
	}
	position, err := decodeDocumentPosition(input.Cursor, "documents.search", fingerprint, input.Sort)
	if err != nil {
		return result, err
	}
	err = pgx.BeginTxFunc(ctx, s.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, documentSearchTransactionSettings); err != nil {
			return err
		}
		indexed := input.UsesEmbeddings() && input.Sort == "relevance"
		args := []any{a.AccountID, input.Tags, input.Sender, input.Recipient, input.Query, input.SenderMatch, input.RecipientMatch, input.Kinds}
		if input.UsesEmbeddings() {
			if len(vector) != m.EmbeddingDimensions {
				return m.ErrUnavailable
			}
			configuration, err := readConfiguration(ctx, tx)
			if err != nil {
				return err
			}
			if input.Space != configuration.EmbeddingSpace() {
				return m.ErrConflict
			}
			args[4], err = json.Marshal(input.Space)
			if err != nil {
				return err
			}
			args = append(args, vector)
			if input.Mode == "hybrid" {
				args = append(args, input.Query)
			}
			if indexed {
				if _, err := tx.Exec(ctx, documentVectorSearchSettings); err != nil {
					return err
				}
			}
		}
		for {
			query := fulltextSearch
			if input.UsesEmbeddings() {
				query = documentSemanticSearch(indexed)
				if input.Mode == "hybrid" {
					query = documentHybridSearch(indexed)
				}
			}
			result, err = readDocumentSearchPage(ctx, tx, input, position, fingerprint, query, args)
			if err != nil || !indexed || result.NextCursor != "" {
				return err
			}
			indexed = false
		}
	})
	return result, documentError(err)
}

func readDocumentSearchPage(ctx context.Context, tx pgx.Tx, input m.DocumentSearchInput, position *documentPosition, fingerprint string, query string, arguments []any) (r.DocumentSearchRecord, error) {
	result := r.DocumentSearchRecord{Items: []r.DocumentSearchItemRecord{}}
	args := append([]any(nil), arguments...)
	seek := searchSeek(input.Sort, position, &args)
	args = append(args, input.Limit+1, input.Offset)
	page := fmt.Sprintf(" LIMIT $%d OFFSET $%d", len(args)-1, len(args))
	order := searchOrder(input.Sort, "")
	totals := "SELECT count(*) AS total FROM ranked"
	if input.UsesEmbeddings() {
		totals = "SELECT NULL::bigint AS total"
	}
	projection := query + ", page AS (SELECT * FROM ranked" + seek + " ORDER BY " + order + page + ") " +
		"SELECT COALESCE(page.id::text,''),COALESCE(page.title,''),COALESCE(page.kind,''),COALESCE(page.tags,'{}'::text[]),COALESCE(page.created_at,'epoch'::timestamptz),COALESCE(page.document_date,''),COALESCE(page.state,''),COALESCE(page.score,0),COALESCE(page.snippet,''),COALESCE(page.lower_title,''),f.sha256,f.media_type,f.size,totals.total,COALESCE(t.source_sha256,''),COALESCE(t.sha256,''),COALESCE(t.media_type,''),COALESCE(t.size,0),COALESCE(t.width,0),COALESCE(t.height,0),COALESCE(t.renderer_revision,0) FROM (" + totals + ") totals LEFT JOIN page ON true " +
		"LEFT JOIN document_files f ON f.document_id=page.id AND f.account_id=$1 LEFT JOIN document_thumbnails t ON t.account_id=f.account_id AND t.document_id=f.document_id AND t.source_sha256=f.sha256 AND t.renderer_revision=1 ORDER BY " + searchOrder(input.Sort, "page.")
	rows, err := tx.Query(ctx, projection, args...)
	if err != nil {
		return result, err
	}
	defer rows.Close()
	var last documentPosition
	for rows.Next() {
		var item r.DocumentSearchItemRecord
		var thumbnail r.DocumentThumbnailRecord
		var titleKey string
		var sha, mediaType *string
		var size *int64
		if err = rows.Scan(&item.Document.ID, &item.Document.Title, &item.Document.Kind, &item.Document.Tags, &item.Document.CreatedAt, &item.Document.DocumentDate, &item.Document.ProcessingState, &item.Score, &item.Snippet, &titleKey, &sha, &mediaType, &size, &result.Total, &thumbnail.SourceSHA256, &thumbnail.SHA256, &thumbnail.MediaType, &thumbnail.Size, &thumbnail.Width, &thumbnail.Height, &thumbnail.RendererRevision); err != nil {
			return result, err
		}
		if thumbnail.SHA256 != "" {
			item.Document.Thumbnail = &thumbnail
		}
		if item.Document.ID == "" {
			continue
		}
		if sha != nil && mediaType != nil && size != nil {
			item.Document.Original = &r.DocumentSearchOriginalRecord{SHA256: *sha, MediaType: *mediaType, Size: *size}
		}
		if math.IsNaN(item.Score) || math.IsInf(item.Score, 0) {
			return result, m.ErrUnavailable
		}
		item.Document.CreatedAt = item.Document.CreatedAt.UTC()
		result.Items = append(result.Items, item)
		if len(result.Items) <= input.Limit {
			last = documentPosition{ID: item.Document.ID, CreatedAt: item.Document.CreatedAt, Title: titleKey, Date: item.Document.DocumentDate, Score: item.Score}
		}
	}
	if err := rows.Err(); err != nil {
		return result, err
	}
	if len(result.Items) > input.Limit {
		result.Items = result.Items[:input.Limit]
		result.NextCursor, err = encodeDocumentPosition("documents.search", fingerprint, input.Sort, last)
		return result, err
	}
	return result, nil
}
