//go:build integration

package repos_test

import (
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"reflect"
	"strings"
	"testing"
)

func TestDocumentJobCountsRespectScopeAndIgnoreFacetsAndPagination(t *testing.T) {
	f := newIngestionFixture(t)
	aiIndependentEnableProperties(t, f)
	first := f.accept(t, f.actor, strings.Repeat("1", 64), "First")
	aiIndependentReady(t, f, first, "First searchable text")
	second := f.accept(t, f.actor, strings.Repeat("2", 64), "Second")
	aiIndependentReady(t, f, second, "Second searchable text")
	f.accept(t, f.actor, strings.Repeat("3", 64), "Waiting")
	foreign := f.addActor(t)
	f.accept(t, foreign, strings.Repeat("4", 64), "Private")
	expected := map[[2]string]int64{{"ingestion", "succeeded"}: 2, {"ingestion", "queued"}: 1, {"ai", "queued"}: 2}
	var cursor string
	for _, query := range []m.DocumentProcessingPageInput{{Limit: 1}, {Limit: 1, Pipeline: "ai"}, {Limit: 1, Status: "failed"}, {Limit: 1, ActiveOnly: true}} {
		page, err := f.service.Jobs(t.Context(), f.actor, query)
		if err != nil {
			t.Fatal(err)
		}
		counts := map[[2]string]int64{}
		for _, group := range page.Counts {
			counts[[2]string{group.Pipeline, group.Status}] = group.Count
		}
		if !reflect.DeepEqual(counts, expected) {
			t.Fatalf("facets altered totals: %+v: %v", query, counts)
		}
		if query.ActiveOnly {
			for _, item := range page.Items {
				if item.Status != "queued" && item.Status != "running" {
					t.Fatalf("terminal active item: %+v", item)
				}
			}
		}
		if query.Pipeline == "" && query.Status == "" && !query.ActiveOnly {
			cursor = page.NextCursor
		}
	}
	if _, err := f.service.Jobs(t.Context(), f.actor, m.DocumentProcessingPageInput{Limit: 1, Cursor: cursor, ActiveOnly: true}); err == nil {
		t.Fatal("active filter accepted an unfiltered cursor")
	}
	page, err := f.service.Jobs(t.Context(), f.actor, m.DocumentProcessingPageInput{Limit: 1, Cursor: cursor})
	if err != nil || len(page.Counts) != 3 {
		t.Fatalf("continuation totals: %+v %v", page, err)
	}
	scoped, err := f.service.Jobs(t.Context(), f.actor, m.DocumentProcessingPageInput{Limit: 1, DocumentID: first.ID})
	if err != nil {
		t.Fatal(err)
	}
	var total int64
	for _, group := range scoped.Counts {
		total += group.Count
	}
	if total != 2 {
		t.Fatalf("document scope: %v", scoped.Counts)
	}
	if err := f.service.Delete(t.Context(), f.actor, second.ID); err != nil {
		t.Fatal(err)
	}
	deleted, err := f.service.Jobs(t.Context(), f.actor, m.DocumentProcessingPageInput{Limit: 1})
	if err != nil {
		t.Fatal(err)
	}
	total = 0
	for _, group := range deleted.Counts {
		total += group.Count
	}
	if total != 5 {
		t.Fatalf("lost deleted-document history: %v", deleted.Counts)
	}
	issue12Grant(t, f, f.actor, []string{})
	if _, err := f.service.Jobs(t.Context(), f.actor, m.DocumentProcessingPageInput{Limit: 1}); !errors.Is(err, m.ErrForbidden) {
		t.Fatalf("counts bypassed revoked permission: %v", err)
	}
}

func TestActiveReindexPagesKeepScopedTotalsAndBindCursor(t *testing.T) {
	f := newIngestionFixture(t)
	foreign := f.addActor(t)
	for index, row := range []struct{ id, account, status string }{
		{"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1", f.actor.AccountID, "running"},
		{"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2", f.actor.AccountID, "enumerating"},
		{"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3", f.actor.AccountID, "succeeded"},
		{"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4", foreign.AccountID, "running"},
	} {
		_, err := f.connection.Exec(t.Context(), `INSERT INTO document_reindex_batches(id,account_id,reason,configuration_revision,configuration_fingerprint,cutoff_sequence,status) VALUES($1,$2,'manual',$4,repeat('a',64),0,$3)`, row.id, row.account, row.status, index+1)
		if err != nil {
			t.Fatal(err)
		}
	}
	first, err := f.service.Batches(t.Context(), f.actor, false, m.DocumentProcessingPageInput{Limit: 1, ActiveOnly: true})
	if err != nil || len(first.Items) != 1 || first.NextCursor == "" {
		t.Fatalf("first active page: %+v %v", first, err)
	}
	totals := map[string]int64{}
	for _, count := range first.Counts {
		totals[count.Status] = count.Count
	}
	if !reflect.DeepEqual(totals, map[string]int64{"enumerating": 1, "running": 1, "succeeded": 1}) {
		t.Fatalf("scope/page affected totals: %v", totals)
	}
	second, err := f.service.Batches(t.Context(), f.actor, false, m.DocumentProcessingPageInput{Limit: 1, ActiveOnly: true, Cursor: first.NextCursor})
	if err != nil || len(second.Items) != 1 || second.NextCursor != "" || first.Items[0].ID == second.Items[0].ID {
		t.Fatalf("second active page: %+v %v", second, err)
	}
	for _, item := range append(first.Items, second.Items...) {
		if item.Status != "enumerating" && item.Status != "running" {
			t.Fatalf("terminal active batch: %+v", item)
		}
	}
	if _, err := f.service.Batches(t.Context(), f.actor, false, m.DocumentProcessingPageInput{Limit: 1, Cursor: first.NextCursor}); err == nil {
		t.Fatal("active cursor accepted without filter")
	}
}
