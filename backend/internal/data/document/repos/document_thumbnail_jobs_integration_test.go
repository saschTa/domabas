//go:build integration

package repos_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	"github.com/google/uuid"
)

func TestThumbnailJobHistoryPaginationAuthorityAndEvidence(t *testing.T) {
	f := newIngestionFixture(t)
	ctx := t.Context()
	hash := strings.Repeat("a", 64)
	doc := f.accept(t, f.actor, hash, "Thumbnail source title")
	ids := []string{uuid.NewString(), uuid.NewString(), uuid.NewString()}
	for i, id := range ids {
		f.exec(t, `INSERT INTO document_thumbnail_jobs(id,account_id,document_id,source_sha256,renderer_revision,attempt,workflow_id,created_at) VALUES($1,$2,$3,$4,1,$5,$6,'2026-09-24T12:00:00Z')`, id, f.actor.AccountID, doc.ID, hash, i+1, "thumbnail-history/"+id)
	}
	f.exec(t, `UPDATE document_thumbnail_jobs SET status='running' WHERE id=$1`, ids[0])
	f.exec(t, `UPDATE document_thumbnail_jobs SET status='failed',failure_code='invalid_file' WHERE id=$1`, ids[0])
	f.exec(t, `UPDATE document_thumbnail_jobs SET status='obsolete' WHERE id=$1`, ids[1])
	input := m.DocumentProcessingPageInput{Limit: 1, Pipeline: "thumbnail"}
	seen := map[string]bool{}
	for {
		page, err := f.service.Jobs(ctx, f.actor, input)
		if err != nil || len(page.Items) != 1 {
			t.Fatalf("thumbnail page: %+v %v", page, err)
		}
		job := page.Items[0]
		if seen[job.ID] || job.Pipeline != "thumbnail" || job.Configuration != nil || job.Generation != nil || job.TextSource != nil || job.ConfigurationRevision != nil || job.ConfigurationFingerprint != nil || job.RendererRevision == nil || *job.RendererRevision != 1 || job.DocumentTitle == nil || *job.DocumentTitle != doc.Title {
			t.Fatalf("invalid typed history or repeated item: %+v", job)
		}
		seen[job.ID] = true
		counts := map[string]int64{}
		for _, count := range page.Counts {
			if count.Pipeline == "thumbnail" {
				counts[count.Status] = count.Count
			}
		}
		if counts["queued"] != 1 || counts["failed"] != 1 || counts["superseded"] != 1 {
			t.Fatalf("full-history normalized totals changed with cursor: %+v", counts)
		}
		if page.NextCursor == "" {
			break
		}
		if _, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{Limit: 1, Cursor: page.NextCursor, Pipeline: "ingestion"}); !issue12Validation(err) {
			t.Fatalf("cursor accepted different pipeline: %v", err)
		}
		input.Cursor = page.NextCursor
	}
	if len(seen) != 3 {
		t.Fatalf("lost thumbnail history: %v", seen)
	}
	failed, err := f.service.JobHistory(ctx, f.actor, ids[0])
	if err != nil || failed.Stage != "rendering" || failed.StartedAt == nil || failed.FinishedAt == nil || failed.FinishedAt.Before(*failed.StartedAt) || failed.FailureCode == nil || *failed.FailureCode != "invalid_file" || failed.IsCurrent {
		t.Fatalf("failed render evidence: %+v %v", failed, err)
	}
	filtered, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{Pipeline: "thumbnail", Status: "superseded", DocumentID: doc.ID})
	if err != nil || len(filtered.Items) != 1 || filtered.Items[0].ID != ids[1] || filtered.Items[0].StartedAt != nil || filtered.Items[0].IsCurrent {
		t.Fatalf("superseded filter/evidence: %+v %v", filtered, err)
	}
	current, err := f.service.JobHistory(ctx, f.actor, ids[2])
	if err != nil || !current.IsCurrent || current.Reason != "retry" || current.StartedAt != nil || current.FinishedAt != nil {
		t.Fatalf("current waiting attempt: %+v %v", current, err)
	}
	all, err := f.service.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{})
	if err != nil || len(all.Items) != 4 {
		t.Fatalf("combined ingestion and thumbnail history: %+v %v", all, err)
	}
	foreign := f.addActor(t)
	if _, err := f.service.JobHistory(ctx, foreign, ids[2]); !errors.Is(err, m.ErrNotFound) {
		t.Fatalf("foreign thumbnail detail leaked: %v", err)
	}
	foreignPage, err := f.service.Jobs(ctx, foreign, m.DocumentProcessingPageInput{Pipeline: "thumbnail"})
	if err != nil || len(foreignPage.Items) != 0 || len(foreignPage.Counts) != 0 {
		t.Fatalf("foreign thumbnail page/count leak: %+v %v", foreignPage, err)
	}
	restricted := services.NewDocumentIngestionService(f.repository, nil, nil, documentDeniedAuthority{authority: f.authority, claim: "documents:read"}, time.Now)
	hidden, err := restricted.JobHistory(ctx, f.actor, ids[2])
	if err != nil || hidden.DocumentTitle != nil {
		t.Fatalf("job-only authority leaked title: %+v %v", hidden, err)
	}
	f.exec(t, `UPDATE document_files SET sha256=$2 WHERE document_id=$1`, doc.ID, strings.Repeat("b", 64))
	changed, err := f.service.JobHistory(ctx, f.actor, ids[2])
	if err != nil || changed.IsCurrent {
		t.Fatalf("changed original kept obsolete thumbnail current: %+v %v", changed, err)
	}
	if err := f.service.Delete(ctx, f.actor, doc.ID); err != nil {
		t.Fatal(err)
	}
	deleted, err := f.service.JobHistory(ctx, f.actor, ids[0])
	if err != nil || !deleted.DocumentDeleted || deleted.DocumentTitle != nil || deleted.IsCurrent {
		t.Fatalf("deleted source lost or disclosed history: %+v %v", deleted, err)
	}
	denied := services.NewDocumentIngestionService(f.repository, nil, nil, documentDeniedAuthority{authority: f.authority, claim: "documents:jobs:read"}, time.Now)
	if _, err := denied.Jobs(ctx, f.actor, m.DocumentProcessingPageInput{Pipeline: "thumbnail"}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("thumbnail jobs bypassed claim: %v", err)
	}
}
