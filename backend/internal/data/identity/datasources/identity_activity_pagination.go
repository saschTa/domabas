package datasources

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/identity/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func readActivity(ctx context.Context, tx pgx.Tx, args []any, actor r.IdentityRecord, finished bool, cursor string) ([]r.IdentityActivityRecord, string, error) {
	operation, column, status, limit := "activity-active", "created_at", "IN", 20
	if finished {
		operation, column, status, limit = "activity-finished", "finished_at", "NOT IN", 5
	}
	fingerprint, err := pagination.Fingerprint([]any{actor.User.ID, actor.Account.ID, limit})
	if err != nil {
		return nil, "", err
	}
	var at *time.Time
	var id *uuid.UUID
	var kind string
	if cursor != "" {
		key, err := pagination.Decode(cursor, operation, fingerprint, "time_desc_kind_id_asc")
		if err != nil || len(key) != 3 || json.Unmarshal(key["at"], &at) != nil || at == nil || at.IsZero() || json.Unmarshal(key["id"], &id) != nil || id == nil || *id == uuid.Nil || json.Unmarshal(key["kind"], &kind) != nil || (kind != "email_retrieval" && kind != "document_processing" && kind != "reindex_batch") {
			return nil, "", r.ErrActivityCursor
		}
	}
	filter := fmt.Sprintf("WHERE status %s ('queued','running') AND %s IS NOT NULL AND ($6::timestamptz IS NULL OR %s<$6 OR (%s=$6 AND (kind,id)>($7,$8::uuid))) ORDER BY %s DESC,kind,id LIMIT $9", status, column, column, column, column)
	values := append(append([]any{}, args...), at, kind, id, limit+1)
	rows, err := tx.Query(ctx, personalActivityUnion+filter, values...)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	items := []r.IdentityActivityRecord{}
	for rows.Next() {
		item, err := scanActivity(rows)
		if err != nil {
			return nil, "", err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	next := ""
	if len(items) > limit {
		items = items[:limit]
		last := items[limit-1]
		position := last.CreatedAt
		if finished {
			position = *last.FinishedAt
		}
		next, err = pagination.Encode(operation, fingerprint, "time_desc_kind_id_asc", map[string]any{"at": position, "kind": last.Kind, "id": last.ID})
	}
	return items, next, err
}
