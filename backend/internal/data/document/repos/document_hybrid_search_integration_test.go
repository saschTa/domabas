//go:build integration

package repos_test

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

func TestHybridSearchRecallRankingAndCursors(t *testing.T) {
	f := newIngestionFixture(t)
	create := func(title string) string {
		t.Helper()
		id := uuid.NewString()
		if _, err := f.documents.Create(t.Context(), f.actor.AccountID, m.Document{ID: id, Title: title, CreatedAt: time.Now()}); err != nil {
			t.Fatal(err)
		}
		return id
	}
	title := create("Invoice")
	property := create("Property match")
	f.exec(t, `UPDATE documents SET tags=ARRAY['invoice'],sender='Billing@example.test',bcc=ARRAY['Owner@example.test'] WHERE id=$1`, property)
	typo := create("Invioce")
	body := f.accept(t, f.actor, strings.Repeat("a", 64), "Archive")
	f.ready(t, body, strings.Repeat("Invoice ", 200), unitVector(1))
	bodyTypo := f.accept(t, f.actor, strings.Repeat("b", 64), "Scanned original")
	f.ready(t, bodyTypo, "Invioce paid", unitVector(1))
	semantic := f.accept(t, f.actor, strings.Repeat("c", 64), "Payment request")
	f.ready(t, semantic, "The amount owed for services is due next month.", unitVector(0))
	unrelated := f.accept(t, f.actor, strings.Repeat("d", 64), "Gardening")
	f.ready(t, unrelated, "Seeds and flowers", unitVector(1))
	foreign := f.addActor(t)
	f.accept(t, foreign, strings.Repeat("e", 64), "Invoice")
	input := m.DocumentSearchInput{Mode: "hybrid", Query: "invoice", Space: m.DefaultConfiguration().EmbeddingSpace(), Limit: 2}
	var ids []string
	var scores []float64
	for range 4 {
		result, err := f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil || result.Total != nil {
			t.Fatalf("hybrid recall: %+v %v", result, err)
		}
		for _, item := range result.Items {
			ids = append(ids, item.Document.ID)
			scores = append(scores, item.Score)
		}
		if result.NextCursor == "" {
			break
		}
		input.Cursor = result.NextCursor
	}
	if len(ids) != 6 || !slices.Contains(ids[:2], title) || !slices.Contains(ids[:2], property) || !slices.Equal(ids[2:], []string{typo, body.ID, bodyTypo.ID, semantic.ID}) {
		t.Fatalf("metadata, text and meaning order: %v scores %v", ids, scores)
	}
	for i := 1; i < len(scores); i++ {
		if scores[i] > scores[i-1] {
			t.Fatalf("cursor order changed: %v", scores)
		}
	}
	input.Cursor, input.Offset = "", 2
	page, err := f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || len(page.Items) != 2 || page.Items[0].Document.ID != typo {
		t.Fatalf("offset and cursor orders differ: %+v %v", page, err)
	}
	input.Offset = 100
	page, err = f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || page.Total != nil || len(page.Items) != 0 || page.NextCursor != "" {
		t.Fatalf("empty page lost the total: %+v %v", page, err)
	}
	input.Offset, input.Tags, input.Sender, input.Recipient = 0, []string{"invoice"}, "billing@EXAMPLE.test", "owner@example.test"
	input.SenderMatch, input.RecipientMatch = "exact", "exact"
	filtered, err := f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || filtered.Total != nil || len(filtered.Items) != 1 || filtered.Items[0].Document.ID != property {
		t.Fatalf("hybrid filters: %+v %v", filtered, err)
	}
	input.Tags, input.Sender, input.Recipient = nil, "", ""
	input.Query = "???"
	punctuation, err := f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || punctuation.Total != nil || len(punctuation.Items) != 0 {
		t.Fatalf("punctuation matched semantic corpus: %+v %v", punctuation, err)
	}
	input.Query = ""
	empty, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil || empty.Total == nil || *empty.Total != 7 {
		t.Fatalf("empty hybrid requires no embedding: %+v %v", empty, err)
	}
}

func TestHybridSearchCurrentTextSpaceAndAuthority(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("a", 64), "Stored original")
	f.ready(t, doc, "The car needs maintenance.", unitVector(0))
	input := m.DocumentSearchInput{Mode: "hybrid", Query: "automobile repair", Space: m.DefaultConfiguration().EmbeddingSpace()}
	search := func(query string) m.DocumentSearchResults {
		t.Helper()
		input.Query = query
		result, err := f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil {
			t.Fatal(err)
		}
		return result
	}
	if len(search(input.Query).Items) != 1 {
		t.Fatal("semantic-only match missing")
	}
	f.exec(t, `UPDATE document_processing SET state='processing',stage='embedding' WHERE document_id=$1`, doc.ID)
	if len(search("automobile repair").Items) != 0 || len(search("maintenence").Items) != 1 {
		t.Fatal("pending generations must expose current fuzzy text but no semantic vectors")
	}
	f.exec(t, `UPDATE document_processing SET state='ready',stage='complete',ocr_revision=ocr_revision+1 WHERE document_id=$1`, doc.ID)
	if len(search("automobile repair").Items) != 0 {
		t.Fatal("stale OCR vectors were searched")
	}
	f.exec(t, `UPDATE document_processing SET generation=generation+1 WHERE document_id=$1`, doc.ID)
	if len(search("maintenence").Items) != 0 {
		t.Fatal("superseded lexical text was searched")
	}
	f.exec(t, `DELETE FROM sessions WHERE digest=$1`, f.actor.SessionDigest)
	if _, err := f.search(t.Context(), f.actor, input, unitVector(0)); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("revoked session: %v", err)
	}
}

func TestHybridFuzzyWordsRequireAllTermsAndExactShortNumbers(t *testing.T) {
	f := newIngestionFixture(t)
	for _, tc := range []struct {
		query, text string
		match       bool
	}{
		{"invioce", "Invoice for electricity", true},
		{"invoice maintenence", "Maintenance invoice", true},
		{"invoice missing", "Invoice for electricity", false},
		{"1234", "1235", false},
		{"car", "cart", false},
		{"RECHNUG", "Die Rechnung", true},
		{"???", "Invoice", false},
	} {
		var score float64
		err := f.connection.QueryRow(t.Context(), `SELECT document_fuzzy_score(tsvector_to_array(to_tsvector('simple',$1)),to_tsvector('simple',$2))`, tc.query, tc.text).Scan(&score)
		if err != nil || (score >= .3) != tc.match {
			t.Errorf("%q in %q: %f %v", tc.query, tc.text, score, err)
		}
	}
}

func TestHybridSearchBeyondFormerCapacity(t *testing.T) {
	f := newIngestionFixture(t)
	vector := unitVector(0)
	for i := range 17 {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+1), fmt.Sprintf("Invoice %d", i))
		f.ready(t, doc, "Maintenance payment request", vector)
		if i < 16 {
			f.exec(t, `INSERT INTO document_chunks(account_id,document_id,generation,position,content,embedding,model_digest) SELECT $1,$2,1,g,'Maintenance payment request',$3,$4 FROM generate_series(1,255) g`, f.actor.AccountID, doc.ID, vector, m.EmbeddingDigest)
		}
		if i == 15 {
			start := time.Now()
			result, err := f.search(t.Context(), f.actor, m.DocumentSearchInput{Mode: "hybrid", Query: "maintenence payment", Space: m.DefaultConfiguration().EmbeddingSpace()}, vector)
			t.Logf("4096-chunk hybrid search: %s", time.Since(start))
			if err != nil || result.Total != nil || len(result.Items) != 16 {
				t.Fatalf("full bounded corpus: %+v %v", result, err)
			}
			if time.Since(start) > 10*time.Second {
				t.Fatal("hybrid search exceeded its ten-second SQL budget")
			}
		}
	}
	input := m.DocumentSearchInput{Mode: "hybrid", Query: "invoice", Space: m.DefaultConfiguration().EmbeddingSpace()}
	if result, err := f.search(t.Context(), f.actor, input, vector); err != nil || result.Total != nil || len(result.Items) != 17 {
		t.Fatalf("hybrid corpus beyond former limit: %+v %v", result, err)
	}
	textInput := m.DocumentSearchInput{Mode: "fulltext", Query: "invoice", Limit: 10, Sort: "title"}
	textPage, err := f.search(t.Context(), f.actor, textInput, nil)
	if err != nil || textPage.Total == nil || *textPage.Total != 17 || len(textPage.Items) != 10 || textPage.NextCursor == "" {
		t.Fatalf("full-text search must search the complete corpus: %+v %v", textPage, err)
	}
	textInput.Cursor = textPage.NextCursor
	textPage, err = f.search(t.Context(), f.actor, textInput, nil)
	if err != nil || textPage.Total == nil || *textPage.Total != 17 || len(textPage.Items) != 7 || textPage.NextCursor != "" {
		t.Fatalf("full-text search must preserve pagination: %+v %v", textPage, err)
	}
	f.exec(t, `UPDATE documents SET tags=ARRAY['narrow'] WHERE title='Invoice 16'`)
	input.Tags = []string{"narrow"}
	result, err := f.search(t.Context(), f.actor, input, vector)
	if err != nil || result.Total != nil || len(result.Items) != 1 {
		t.Fatalf("filters must precede candidate selection: %+v %v", result, err)
	}
	f.exec(t, `UPDATE documents SET kind='email' WHERE title='Invoice 16'`)
	input.Tags, input.Kinds = nil, []string{"email"}
	for _, mode := range []string{"hybrid", "semantic"} {
		input.Mode = mode
		result, err = f.search(t.Context(), f.actor, input, vector)
		if err != nil || result.Total != nil || len(result.Items) != 1 || result.Items[0].Document.Kind != "email" {
			t.Fatalf("kind must precede %s candidate selection: %+v %v", mode, result, err)
		}
	}
}
