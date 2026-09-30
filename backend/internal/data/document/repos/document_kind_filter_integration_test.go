//go:build integration

package repos_test

import (
	"fmt"
	"slices"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestDocumentKindsFilterEverySearchModeBeforePagination(t *testing.T) {
	f := newIngestionFixture(t)
	for i, kind := range []string{"document", "letter", "email", "email", "document"} {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+1), fmt.Sprintf("Invoice %d", i))
		f.ready(t, doc, "Invoice payment", unitVector(0))
		f.exec(t, `UPDATE documents SET kind=$2,tags=ARRAY['work'],sender='Sender',bcc=ARRAY['Recipient'] WHERE id=$1`, doc.ID, kind)
	}
	foreign := f.addActor(t)
	f.accept(t, foreign, fmt.Sprintf("%064x", 99), "Invoice foreign")
	for _, mode := range []string{"fulltext", "hybrid", "semantic"} {
		for _, test := range []struct {
			kinds []string
			total int64
		}{
			{nil, 5}, {[]string{}, 5}, {[]string{"email"}, 2},
			{[]string{"letter", "document"}, 3}, {[]string{"letter", "email"}, 3},
			{[]string{"document", "letter", "email"}, 5},
		} {
			t.Run(fmt.Sprintf("%s/%v", mode, test.kinds), func(t *testing.T) {
				input := m.DocumentSearchInput{Mode: mode, Query: "invoice", Kinds: test.kinds, Limit: 1, Sort: "title", Space: m.DefaultConfiguration().EmbeddingSpace()}
				seen := map[string]bool{}
				for range 6 {
					result, err := f.search(t.Context(), f.actor, input, unitVector(0))
					if err != nil || !searchTotalMatches(mode, result.Total, test.total) || len(result.Items) != 1 {
						t.Fatalf("filtered page: %+v %v", result, err)
					}
					doc := result.Items[0].Document
					if seen[doc.ID] || len(test.kinds) > 0 && !slices.Contains(test.kinds, doc.Kind) {
						t.Fatalf("duplicate or excluded result: %+v", doc)
					}
					seen[doc.ID] = true
					if result.NextCursor == "" {
						break
					}
					input.Cursor = result.NextCursor
				}
				if int64(len(seen)) != test.total {
					t.Fatalf("missing results: %v", seen)
				}
			})
		}
		input := m.DocumentSearchInput{Mode: mode, Query: "invoice", Kinds: []string{"email"}, Tags: []string{"work"}, Sender: "sender", Recipient: "recipient", SenderMatch: "exact", RecipientMatch: "exact", Limit: 1, Space: m.DefaultConfiguration().EmbeddingSpace()}
		page, err := f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil || !searchTotalMatches(mode, page.Total, 2) || page.NextCursor == "" {
			t.Fatalf("combined filters: %+v %v", page, err)
		}
		input.Cursor, input.Kinds = page.NextCursor, []string{"document"}
		if _, err = f.search(t.Context(), f.actor, input, unitVector(0)); err == nil {
			t.Fatal("cursor reused across kinds")
		}
		input.Cursor, input.Tags = "", []string{"absent"}
		page, err = f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil || !searchTotalMatches(mode, page.Total, 0) || len(page.Items) != 0 || page.NextCursor != "" {
			t.Fatalf("empty combined result: %+v %v", page, err)
		}
	}
	for _, mode := range []string{"fulltext", "hybrid"} {
		page, err := f.search(t.Context(), f.actor, m.DocumentSearchInput{Mode: mode, Kinds: []string{"document", "letter"}}, nil)
		if err != nil || page.Total == nil || *page.Total != 3 {
			t.Fatalf("filter-only %s search: %+v %v", mode, page, err)
		}
	}
}
