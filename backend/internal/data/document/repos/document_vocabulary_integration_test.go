//go:build integration

package repos_test

import (
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"testing"
)

func TestVocabularyStoredValuesCursorAndExactSearch(t *testing.T) {
	f := newIngestionFixture(t)
	vocabulary := vocabularyRepository(t, f)
	first := f.accept(t, f.actor, "1111111111111111111111111111111111111111111111111111111111111111", "first")
	second := f.accept(t, f.actor, "2222222222222222222222222222222222222222222222222222222222222222", "second")
	f.exec(t, `UPDATE documents SET tags=ARRAY['alpha','beta'],sender='Alice@Example.test',cc=ARRAY['Bob@Example.test'] WHERE id=$1`, first.ID)
	f.exec(t, `UPDATE documents SET tags=ARRAY['beta','gamma'],sender='alice@example.test',bcc=ARRAY['prefixBob@Example.test'] WHERE id=$1`, second.ID)
	input := m.DocumentVocabularyInput{Field: "tag", Limit: 2}
	page, err := vocabulary.List(t.Context(), f.actor, input)
	if err != nil || len(page.Items) != 2 || page.Items[0].Value != "alpha" || page.Items[1].Value != "beta" || page.NextCursor == "" {
		t.Fatalf("first distinct vocabulary page: %+v %v", page, err)
	}
	input.Cursor = page.NextCursor
	page, err = vocabulary.List(t.Context(), f.actor, input)
	if err != nil || len(page.Items) != 1 || page.Items[0].Value != "gamma" || page.NextCursor != "" {
		t.Fatalf("vocabulary continuation: %+v %v", page, err)
	}
	page, err = vocabulary.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: "sender", Limit: 40})
	if err != nil || len(page.Items) != 1 || page.Items[0].Value != "Alice@Example.test" || len(page.Items[0].Key) != 64 {
		t.Fatalf("folded sender identity: %+v %v", page, err)
	}
	key := page.Items[0].Key
	f.exec(t, `UPDATE documents SET sender='alice@example.test' WHERE id=$1`, first.ID)
	page, err = vocabulary.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: "sender", Limit: 40})
	if err != nil || len(page.Items) != 1 || page.Items[0].Key != key || page.Items[0].Value != "alice@example.test" {
		t.Fatalf("representative churn changed identity: %+v %v", page, err)
	}
	page, err = vocabulary.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: "recipient", Query: "BOB@", Limit: 40})
	if err != nil || len(page.Items) != 2 {
		t.Fatalf("recipient union lookup: %+v %v", page, err)
	}
	f.ready(t, first, "first", unitVector(0))
	f.ready(t, second, "second", unitVector(0))
	for _, mode := range []string{"fulltext", "semantic"} {
		input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: mode, Query: "first OR second", Sender: "alice@example.test", SenderMatch: "exact", Recipient: "Bob@Example.test", RecipientMatch: "exact", Limit: 1}
		result, err := f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil || !searchTotalMatches(mode, result.Total, 1) || len(result.Items) != 1 || result.Items[0].Document.ID != first.ID {
			t.Fatalf("%s exact filters: %+v %v", mode, result, err)
		}
		input.RecipientMatch = "contains"
		result, err = f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil || !searchTotalMatches(mode, result.Total, 2) || result.NextCursor == "" {
			t.Fatalf("%s mixed filters: %+v %v", mode, result, err)
		}
	}
	f.exec(t, `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, f.actor.AccountID, f.actor.UserID)
	_, err = vocabulary.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: "tag", Cursor: "malformed", Limit: 2})
	if !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("current authority must precede cursor validation: %v", err)
	}
}
