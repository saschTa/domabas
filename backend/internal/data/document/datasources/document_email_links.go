package datasources

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/jackc/pgx/v5"
)

func emailLinkPage(a m.DocumentActor, id string, limit int, token, operation string) (int, string, error) {
	if err := m.ValidateAccountID(id); err != nil {
		return 0, "", err
	}
	if limit == 0 {
		limit = 20
	}
	if limit < 1 || limit > 50 || len(token) > 4096 {
		return 0, "", cursorFailure()
	}
	fingerprint, err := pagination.Fingerprint(struct {
		Account, Document, Operation string
		Limit                        int
	}{a.AccountID, id, operation, limit})
	return limit, fingerprint, err
}

func mimePath(value string) ([]int, error) {
	parts := strings.Split(value, ".")
	if len(parts) == 0 || len(parts) > 16 {
		return nil, cursorFailure()
	}
	result := make([]int, len(parts))
	for i, part := range parts {
		v, err := strconv.Atoi(part)
		if err != nil || v < 1 || v > 100 || strconv.Itoa(v) != part {
			return nil, cursorFailure()
		}
		result[i] = v
	}
	return result, nil
}

func (s *DocumentDataSource) EmailLinks(ctx context.Context, a m.DocumentActor, id string, limit int, token string) (m.DocumentEmailLinks, error) {
	out := m.DocumentEmailLinks{Attachments: []m.DocumentEmailAttachment{}}
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		var err error
		limit, fingerprint, err := emailLinkPage(a, id, limit, token, "email.links")
		if err != nil {
			return err
		}
		var current string
		if err := tx.QueryRow(ctx, "SELECT id FROM documents WHERE account_id=$1 AND id=$2", a.AccountID, id).Scan(&current); err != nil {
			return err
		}
		position := []int{}
		if token != "" {
			fields, err := pagination.Decode(token, "email.links", fingerprint, "mime-path")
			var path string
			if err != nil || len(fields) != 1 || json.Unmarshal(fields["path"], &path) != nil {
				return cursorFailure()
			}
			position, err = mimePath(path)
			if err != nil {
				return err
			}
		}
		rows, err := tx.Query(ctx, `WITH edges AS (
SELECT DISTINCT ON (p.path) p.path,p.filename,
CASE WHEN p.document_id IS NOT NULL AND d.id IS NULL THEN 'deleted' ELSE p.state END AS status,
p.failure_code,d.id,d.title,f.media_type,d.created_at,string_to_array(p.path,'.')::integer[] AS path_order
FROM email_messages e JOIN email_parts p ON p.message_id=e.id AND p.account_id=e.account_id
LEFT JOIN documents d ON d.account_id=p.account_id AND d.id=p.document_id
LEFT JOIN document_files f ON f.account_id=d.account_id AND f.document_id=d.id
WHERE e.account_id=$1 AND e.parent_document_id=$2 AND p.path<>'0'
ORDER BY p.path,(d.id IS NOT NULL) DESC,(p.state IN ('accepted','reused')) DESC,p.updated_at DESC,p.id DESC
) SELECT path,filename,status,COALESCE(failure_code,''),id,title,media_type,created_at
FROM edges WHERE path_order>$3::integer[] ORDER BY path_order LIMIT $4`, a.AccountID, id, position, limit+1)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var item m.DocumentEmailAttachment
			var documentID, title, media *string
			var link m.DocumentEmailLink
			var at *time.Time
			if err := rows.Scan(&item.Part, &item.Filename, &item.Status, &item.FailureCode, &documentID, &title, &media, &at); err != nil {
				return err
			}
			if documentID != nil && title != nil && media != nil && at != nil {
				link = m.DocumentEmailLink{DocumentID: *documentID, Title: *title, MediaType: *media, CreatedAt: *at}
				item.Document = &link
			}
			out.Attachments = append(out.Attachments, item)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		if len(out.Attachments) > limit {
			out.Attachments = out.Attachments[:limit]
			out.NextCursor, err = pagination.Encode("email.links", fingerprint, "mime-path", struct {
				Path string `json:"path"`
			}{out.Attachments[limit-1].Part})
		}
		return err
	})
	return out, err
}

func (s *DocumentDataSource) EmailParents(ctx context.Context, a m.DocumentActor, id string, limit int, token string) (m.DocumentEmailParents, error) {
	out := m.DocumentEmailParents{Items: []m.DocumentEmailLink{}}
	err := s.scopedReadTx(ctx, a, func(tx pgx.Tx) error {
		limit, fingerprint, err := emailLinkPage(a, id, limit, token, "email.parents")
		if err != nil {
			return err
		}
		var current string
		if err := tx.QueryRow(ctx, "SELECT id FROM documents WHERE account_id=$1 AND id=$2", a.AccountID, id).Scan(&current); err != nil {
			return err
		}
		position, err := decodeDocumentPosition(token, "email.parents", fingerprint, "newest")
		if err != nil {
			return err
		}
		args := []any{a.AccountID, id, limit + 1}
		seek := ""
		if position != nil {
			seek = " AND (d.created_at,d.id)<($4::timestamptz,$5::uuid)"
			args = append(args, position.CreatedAt, position.ID)
		}
		rows, err := tx.Query(ctx, `SELECT d.id,d.title,f.media_type,d.created_at FROM documents d JOIN document_files f ON f.account_id=d.account_id AND f.document_id=d.id WHERE d.account_id=$1 AND EXISTS(SELECT 1 FROM email_messages e JOIN email_parts p ON p.message_id=e.id AND p.account_id=e.account_id WHERE e.account_id=d.account_id AND e.parent_document_id=d.id AND p.document_id=$2 AND p.path<>'0' AND p.state IN ('accepted','reused'))`+seek+` ORDER BY d.created_at DESC,d.id DESC LIMIT $3`, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var item m.DocumentEmailLink
			if err := rows.Scan(&item.DocumentID, &item.Title, &item.MediaType, &item.CreatedAt); err != nil {
				return err
			}
			out.Items = append(out.Items, item)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		if len(out.Items) > limit {
			out.Items = out.Items[:limit]
			last := out.Items[limit-1]
			out.NextCursor, err = encodeDocumentPosition("email.parents", fingerprint, "newest", documentPosition{ID: last.DocumentID, CreatedAt: last.CreatedAt})
		}
		return err
	})
	return out, err
}
