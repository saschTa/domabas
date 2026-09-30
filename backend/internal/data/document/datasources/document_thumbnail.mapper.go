package datasources

import (
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/jackc/pgx/v5"
)

func thumbnailJobMapper(row pgx.Row) (r.DocumentThumbnailJobRecord, error) {
	var j r.DocumentThumbnailJobRecord
	err := row.Scan(&j.ID, &j.AccountID, &j.DocumentID, &j.SourceSHA256, &j.RendererRevision, &j.Attempt, &j.WorkflowID, &j.RunID, &j.TaskQueue, &j.LeaseToken, &j.Status, &j.PermitEnd, &j.AdmittedAt)
	return j, err
}
