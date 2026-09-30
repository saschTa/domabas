//go:build integration

package repos_test

import (
	"errors"
	"fmt"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	"math"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestSearchOriginalProjectionKeepsIndependentAuthorityAndNamespace(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("a", 64), "Original projection")
	f.ready(t, doc, "Original projection", unitVector(0))
	other := f.addActor(t)
	foreign := f.accept(t, other, strings.Repeat("b", 64), "Original projection")
	foreignFixture := *f
	foreignFixture.actor = other
	foreignFixture.ready(t, foreign, "Original projection", unitVector(0))
	for _, mode := range []string{"fulltext", "semantic", "hybrid"} {
		input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: mode, Query: "projection", Limit: 12}
		for _, denied := range []string{"documents:read", "documents:download", "documents:search"} {
			repository := services.NewDocumentIngestionService(f.repository, nil, documentFixtureProcessor{vector: unitVector(0)}, documentDeniedAuthority{authority: f.authority, claim: denied}, time.Now)
			result, err := repository.Search(t.Context(), f.actor, input)
			if denied == "documents:search" {
				if !errors.Is(err, m.ErrForbidden) {
					t.Fatalf("missing search authority accepted: %v", err)
				}
				continue
			}
			if err != nil || (mode == "fulltext" && (result.Total == nil || *result.Total != 1)) || (mode != "fulltext" && result.Total != nil) || len(result.Items) != 1 || result.Items[0].Document.ID != doc.ID {
				t.Fatalf("%s search changed authority or scope when %s denied: %+v %v", mode, denied, result, err)
			}
			original := result.Items[0].Document.Original
			if original == nil || original.SHA256 != doc.File.SHA256 || original.Size != doc.File.Size || original.MediaType != doc.File.MediaType {
				t.Fatalf("search original crossed namespace or changed identity: %+v", original)
			}
		}
	}
}

func TestSearchCursorAllSortsTiesNullDatesAndDeletedBoundary(t *testing.T) {
	f := newIngestionFixture(t)
	titles := []string{"Needle beta", "Needle Alpha", "Needle alpha", "Needle delta", "Needle gamma", "Needle beta", "Needle omega"}
	dates := []string{"2026-09-17", "", "2026-09-17", "2026-01-01", "", "2026-10-01", ""}
	ids := make([]string, len(titles))
	for i, title := range titles {
		ids[i] = fmt.Sprintf("00000000-0000-4000-8000-%012d", i+1)
		_, err := f.documents.Create(t.Context(), f.actor.AccountID, m.Document{ID: ids[i], Title: title, CreatedAt: time.Date(2026, 9, 18, 1, 2, 3, (123456+i/2)*1000, time.UTC)})
		if err != nil {
			t.Fatal(err)
		}
		f.exec(t, `UPDATE documents SET document_date=NULLIF($2,'')::date WHERE id=$1`, ids[i], dates[i])
		if i%2 == 0 {
			f.exec(t, `INSERT INTO document_files(document_id,account_id,uploader_id,original_filename,media_type,size,sha256,ingested_at) VALUES($1,$2,$3,'preview.png','image/png',123,$4,now())`, ids[i], f.actor.AccountID, f.actor.UserID, fmt.Sprintf("%064x", i+1))
		}
	}
	orders := map[string][]int{
		"relevance": {0, 1, 2, 3, 4, 5, 6}, "newest": {6, 5, 4, 3, 2, 1, 0}, "oldest": {0, 1, 2, 3, 4, 5, 6}, "title": {1, 2, 0, 5, 3, 4, 6},
		"date-newest": {5, 0, 2, 3, 1, 4, 6}, "date-oldest": {3, 0, 2, 5, 1, 4, 6},
	}
	for sort, order := range orders {
		t.Run(sort, func(t *testing.T) {
			input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "fulltext", Query: "needle", Sort: sort, Limit: 2}
			got := []string{}
			seen := map[string]bool{}
			for page := 0; page < 10; page++ {
				result, err := f.search(t.Context(), f.actor, input, nil)
				if err != nil {
					t.Fatal(err)
				}
				if result.Total == nil || *result.Total != int64(len(ids)) {
					t.Fatalf("total changed after seek: %d", result.Total)
				}
				for _, item := range result.Items {
					index := slices.Index(ids, item.Document.ID)
					original := item.Document.Original
					if index%2 == 0 {
						if original == nil || original.SHA256 != fmt.Sprintf("%064x", index+1) || original.MediaType != "image/png" || original.Size != 123 {
							t.Fatalf("wrong original on sorted page: %+v", original)
						}
					} else if original != nil {
						t.Fatalf("fileless result gained an original: %+v", original)
					}
					if seen[item.Document.ID] {
						t.Fatalf("duplicate boundary %s", item.Document.ID)
					}
					seen[item.Document.ID] = true
					got = append(got, item.Document.ID)
				}
				if result.NextCursor == "" {
					break
				}
				input.Cursor = result.NextCursor
			}
			want := []string{}
			for _, i := range order {
				want = append(want, ids[i])
			}
			if !slices.Equal(got, want) {
				t.Fatalf("order:\n%v\nwant %v", got, want)
			}
			input.Cursor = ""
			input.Offset = 2
			offset, err := f.search(t.Context(), f.actor, input, nil)
			if err != nil || len(offset.Items) != 2 || offset.Items[0].Document.ID != want[2] || offset.Items[1].Document.ID != want[3] {
				t.Fatalf("legacy offset mismatch: %+v %v", offset, err)
			}
		})
	}
	input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "fulltext", Sort: "title", Limit: 2}
	first, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil {
		t.Fatal(err)
	}
	f.exec(t, `DELETE FROM document_files WHERE document_id=$1`, first.Items[1].Document.ID)
	f.exec(t, `DELETE FROM documents WHERE id=$1`, first.Items[1].Document.ID)
	input.Cursor = first.NextCursor
	next, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil || next.Total == nil || *next.Total != 6 || len(next.Items) != 2 || next.Items[0].Document.ID != ids[0] || next.Items[1].Document.ID != ids[5] {
		t.Fatalf("deleted boundary broke continuation: %+v %v", next, err)
	}
}

func TestSemanticCursorPreservesPgvectorRankingAndPrecisionTies(t *testing.T) {
	f := newIngestionFixture(t)
	x := 1.0
	for i := range 8 {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+200), fmt.Sprintf("Precise ranking %d", i))
		vector := make([]float64, m.EmbeddingDimensions)
		vector[0], vector[1] = x, 1
		f.ready(t, doc, "Precise ranking", vector)
		x = math.Nextafter(x, 2)
	}
	input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "semantic", Query: "ranking", Limit: 20}
	whole, err := f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || len(whole.Items) != 8 {
		t.Fatalf("semantic fixture: %+v %v", whole, err)
	}
	tied := false
	for index := 1; index < len(whole.Items); index++ {
		if whole.Items[index-1].Score == whole.Items[index].Score {
			tied = true
		}
	}
	if !tied {
		t.Fatal("fixture must exercise double precision embeddings that tie after pgvector conversion")
	}
	input.Limit = 1
	for _, expected := range whole.Items {
		page, err := f.search(t.Context(), f.actor, input, unitVector(0))
		if err != nil || len(page.Items) != 1 || page.Total != nil || page.Items[0].Document.ID != expected.Document.ID || page.Items[0].Score != expected.Score {
			t.Fatalf("float8 continuation skipped or repeated rank: %+v want %+v: %v", page, expected, err)
		}
		input.Cursor = page.NextCursor
		if original := page.Items[0].Document.Original; original == nil || expected.Document.Original == nil || *original != *expected.Document.Original {
			t.Fatalf("semantic continuation lost original: %+v", page.Items[0].Document)
		}
	}
	if input.Cursor != "" {
		t.Fatal("last semantic page retained continuation")
	}
}

func TestSearchLiteralAddressTagFiltersAndLegacyUnicodeTitles(t *testing.T) {
	f := newIngestionFixture(t)
	for i, title := range []string{"Invoice one", "Invoice two", "Invoice three", "Invoice four", "Invoice five"} {
		id := fmt.Sprintf("00000000-0000-4000-8000-%012d", i+1)
		if _, err := f.documents.Create(t.Context(), f.actor.AccountID, m.Document{ID: id, Title: title, CreatedAt: time.Now()}); err != nil {
			t.Fatal(err)
		}
		recipientColumn := []string{"recipients", "cc", "bcc", "recipients", "recipients"}[i]
		sender := "A%_Sender"
		recipient := "To%_Recipient"
		tags := []string{"mail", "work"}
		if i == 3 {
			sender = "AXYSender"
			recipient = "ToXYRecipient"
		}
		if i == 4 {
			tags = []string{"mail"}
		}
		f.exec(t, `UPDATE documents SET tags=$2,sender=$3,`+recipientColumn+`=ARRAY[$4::text] WHERE id=$1`, id, tags, sender, recipient)
	}
	input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "fulltext", Sender: "%_sENDER", Recipient: "%_rECIPIENT", Tags: []string{"WORK", "mail"}, Limit: 2}
	first, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil || first.Total == nil || *first.Total != 3 || len(first.Items) != 2 || first.NextCursor == "" {
		t.Fatalf("literal filters/AND tags: %+v %v", first, err)
	}
	input.Cursor = first.NextCursor
	next, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil || next.Total == nil || *next.Total != 3 || len(next.Items) != 1 {
		t.Fatalf("filtered continuation: %+v %v", next, err)
	}
	input.Cursor = ""
	input.Query = "!!!"
	punctuation, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil || punctuation.Total == nil || *punctuation.Total != 0 {
		t.Fatalf("punctuation is not filter-only: %+v %v", punctuation, err)
	}
	for i, title := range []string{strings.Repeat("İ", 200), strings.Repeat("\x01", 200), strings.Repeat("𐐀", 200)} {
		id := fmt.Sprintf("10000000-0000-4000-8000-%012d", i+1)
		f.exec(t, `INSERT INTO documents(id,account_id,title,created_at) VALUES($1,$2,$3,now())`, id, f.actor.AccountID, title)
	}
	input = m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "fulltext", Sort: "title", Limit: 1}
	count := 0
	for count < 10 {
		result, err := f.search(t.Context(), f.actor, input, nil)
		if err != nil {
			t.Fatal(err)
		}
		count += len(result.Items)
		if result.NextCursor == "" {
			break
		}
		input.Cursor = result.NextCursor
	}
	if count != 8 {
		t.Fatalf("legacy expanded/control titles skipped: %d", count)
	}
}

func TestCursorScopeCriteriaAndLaterPageAuthority(t *testing.T) {
	for _, revocation := range []string{"session", "membership"} {
		t.Run(revocation, func(t *testing.T) {
			f := newIngestionFixture(t)
			for i := range 3 {
				if _, err := f.documents.Create(t.Context(), f.actor.AccountID, m.Document{ID: fmt.Sprintf("00000000-0000-4000-8000-%012d", i+1), Title: "needle", CreatedAt: time.Now()}); err != nil {
					t.Fatal(err)
				}
			}
			input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "fulltext", Query: "needle", Limit: 1}
			first, err := f.search(t.Context(), f.actor, input, nil)
			if err != nil {
				t.Fatal(err)
			}
			input.Cursor = first.NextCursor
			changed := input
			changed.Sender = "different"
			if _, err := f.search(t.Context(), f.actor, changed, nil); err == nil {
				t.Fatal("changed criteria reused cursor")
			}
			changed = input
			changed.Limit = 2
			if _, err := f.search(t.Context(), f.actor, changed, nil); err == nil {
				t.Fatal("changed limit reused cursor")
			}
			other := f.addActor(t)
			if _, err := f.search(t.Context(), other, input, nil); err == nil {
				t.Fatal("foreign namespace reused cursor")
			}
			list, err := f.documents.List(t.Context(), f.actor.AccountID, m.DocumentPageRequest{Limit: 1})
			if err != nil {
				t.Fatal(err)
			}
			changed = input
			changed.Cursor = list.NextCursor
			if _, err := f.search(t.Context(), f.actor, changed, nil); err == nil {
				t.Fatal("list cursor reused for search")
			}
			switch revocation {
			case "session":
				f.exec(t, `DELETE FROM sessions WHERE digest=$1`, f.actor.SessionDigest)
			case "membership":
				f.exec(t, `UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2`, f.actor.AccountID, f.actor.UserID)
			}
			_, err = f.search(t.Context(), f.actor, input, nil)
			if !errors.Is(err, m.ErrUnauthorized) && !errors.Is(err, m.ErrForbidden) {
				t.Fatalf("later page ignored revoked %s: %v", revocation, err)
			}
		})
	}
}

func TestFilteredSemanticSearchExcludesStaleGenerationRevisionAndPendingVectors(t *testing.T) {
	f := newIngestionFixture(t)
	ids := make([]string, 5)
	for i := range ids {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", i+100), fmt.Sprintf("Semantic filtered %d", i))
		ids[i] = doc.ID
		f.ready(t, doc, "currentlexicalneedle", unitVector(0))
		f.exec(t, `UPDATE documents SET sender='Sender%_Literal',cc=ARRAY['Recipient%_Literal'],tags=ARRAY['semantic'] WHERE id=$1`, doc.ID)
	}
	f.exec(t, `UPDATE document_chunks SET generation=2 WHERE document_id=$1`, ids[1])
	f.exec(t, `UPDATE document_processing SET ocr_revision=0 WHERE document_id=$1`, ids[2])
	f.exec(t, `UPDATE document_chunks SET embedding=NULL,model_digest=NULL WHERE document_id=$1`, ids[3])
	f.exec(t, `UPDATE document_processing SET state='failed',stage='failed',failure_code='processing_failed' WHERE document_id=$1`, ids[4])
	input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: "semantic", Query: "needle", Sender: "%_literal", Recipient: "%_literal", Tags: []string{"semantic"}, Limit: 1}
	result, err := f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || result.Total != nil || len(result.Items) != 1 || result.Items[0].Document.ID != ids[0] || result.NextCursor != "" {
		t.Fatalf("stale semantic eligibility: %+v %v", result, err)
	}
	input.Mode = "fulltext"
	input.Query = "currentlexicalneedle"
	input.Limit = 20
	lexical, err := f.search(t.Context(), f.actor, input, nil)
	if err != nil || lexical.Total == nil || *lexical.Total != 4 {
		t.Fatalf("current lexical text should remain searchable during indexing/failure: %+v %v", lexical, err)
	}
	if _, err := f.connection.Exec(t.Context(), "UPDATE document_chunks SET model_digest=$2 WHERE document_id=$1", ids[0], strings.Repeat("f", 64)); err != nil {
		t.Fatal(err)
	}
	input.Mode = "semantic"
	input.Query = "needle"
	mismatch, err := f.search(t.Context(), f.actor, input, unitVector(0))
	if err != nil || mismatch.Total != nil || len(mismatch.Items) != 0 {
		t.Fatalf("foreign digest entered semantic space: %+v %v", mismatch, err)
	}
	if _, err := f.connection.Exec(t.Context(), "UPDATE document_chunks SET model_digest='invalid' WHERE document_id=$1", ids[0]); err == nil {
		t.Fatal("malformed embedding digest accepted")
	}
}
