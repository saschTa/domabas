//go:build integration

package repos_test

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	sources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	repos "github.com/domabas/domabas/backend/internal/data/document/repos"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/domain/document/services"
	"github.com/google/uuid"
)

func vocabularyRepository(t *testing.T, f *ingestionFixture) *services.DocumentVocabularyService {
	t.Helper()
	return services.NewDocumentVocabularyService(repos.NewDocumentVocabularyRepository(sources.NewDocumentDataSource(f.source.Database())), f.authority)
}

func vocabularyDocument(t *testing.T, f *ingestionFixture, actor m.DocumentActor, tags []string, sender string, to, cc, bcc []string) string {
	t.Helper()
	id := uuid.NewString()
	f.exec(t, `INSERT INTO documents(id,account_id,title,created_at,tags,sender,recipients,cc,bcc)
 VALUES($1,$2,'Vocabulary fixture',clock_timestamp(),COALESCE($3::text[],'{}'),$4,COALESCE($5::text[],'{}'),COALESCE($6::text[],'{}'),COALESCE($7::text[],'{}'))`, id, actor.AccountID, tags, sender, to, cc, bcc)
	return id
}

func TestVocabularyTraversesMoreThanFourHundredDistinctValues(t *testing.T) {
	f := newIngestionFixture(t)
	repository := vocabularyRepository(t, f)
	for start := 0; start < 451; start += 20 {
		tags := []string{}
		for index := start; index < min(start+20, 451); index++ {
			tags = append(tags, fmt.Sprintf("tag-%03d", index))
		}
		vocabularyDocument(t, f, f.actor, tags, "", nil, nil, nil)
	}
	vocabularyDocument(t, f, f.actor, []string{"tag-000", "tag-040", "tag-450"}, "", nil, nil, nil)
	foreign := f.addActor(t)
	vocabularyDocument(t, f, foreign, []string{"foreign-private"}, "", nil, nil, nil)
	input := m.DocumentVocabularyInput{Field: "tag", Limit: 40}
	seenKeys := map[string]bool{}
	seenCursors := map[string]bool{}
	values := []string{}
	pages := 0
	for {
		page, err := repository.List(t.Context(), f.actor, input)
		if err != nil || len(page.Items) == 0 || len(page.Items) > 40 {
			t.Fatalf("page %d: %d items, %v", pages, len(page.Items), err)
		}
		pages++
		for _, item := range page.Items {
			if seenKeys[item.Key] || item.Value != fmt.Sprintf("tag-%03d", len(values)) {
				t.Fatalf("missing, duplicate or foreign value at %d: %+v", len(values), item)
			}
			seenKeys[item.Key] = true
			values = append(values, item.Value)
		}
		if page.NextCursor == "" {
			break
		}
		if seenCursors[page.NextCursor] || pages > 12 {
			t.Fatal("vocabulary cursor did not advance")
		}
		seenCursors[page.NextCursor] = true
		input.Cursor = page.NextCursor
	}
	if len(values) != 451 || pages != 12 {
		t.Fatalf("corpus was capped: %d values in %d pages", len(values), pages)
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := repository.List(ctx, f.actor, input); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled lookup did not stop: %v", err)
	}
}

func TestVocabularyLiteralUnicodeAndRecipientUnion(t *testing.T) {
	f := newIngestionFixture(t)
	repository := vocabularyRepository(t, f)
	values := []string{"Percent%@example.test", "Under_score@example.test", "Quote'\"@example.test", "Plus+\\&@example.test", "\ufeffAlice@example.test\ufeff", "İ@example.test", "Straße@example.test", "é@example.test", "e\u0301@example.test", "😀@example.test"}
	for index, value := range values {
		metadata, err := (m.DocumentMetadata{Title: "Vocabulary fixture", Tags: []string{value}}).Normalize()
		if err != nil {
			t.Fatal(err)
		}
		var to, cc, bcc []string
		switch index % 3 {
		case 0:
			to = []string{value}
		case 1:
			cc = []string{value}
		case 2:
			bcc = []string{value}
		}
		vocabularyDocument(t, f, f.actor, metadata.Tags, value, to, cc, bcc)
	}
	vocabularyDocument(t, f, f.actor, nil, "percent%@example.test", []string{"percent%@example.test"}, []string{"percent%@example.test"}, []string{"percent%@example.test"})
	vocabularyDocument(t, f, f.actor, nil, "i\u0307@example.test", nil, []string{"i\u0307@example.test"}, nil)
	for _, field := range []string{"sender", "recipient", "tag"} {
		page, err := repository.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: field})
		if err != nil || len(page.Items) != len(values) {
			t.Fatalf("%s distinct union: %d items, %v", field, len(page.Items), err)
		}
		for _, query := range []string{"%", "_", "'\"", "+\\&", "\ufeff", "İ", "straße", "é", "e\u0301", "😀"} {
			page, err := repository.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: field, Query: query})
			want := 1
			if field == "tag" && query == "İ" {
				want = 0
			}
			if err != nil || len(page.Items) != want {
				t.Fatalf("%s literal query %q: %+v %v", field, query, page, err)
			}
			if query == "İ" && field != "tag" {
				key := fmt.Sprintf("%x", sha256.Sum256([]byte(field+"\x00i\u0307@example.test")))
				if page.Items[0].Value != "i\u0307@example.test" || page.Items[0].Key != key {
					t.Fatalf("address identity did not use PostgreSQL lowercase: %+v", page.Items[0])
				}
			}
			if query == "\ufeff" {
				value := values[4]
				if field == "tag" {
					value = strings.ToLower(value)
				}
				if page.Items[0].Value != value {
					t.Fatalf("U+FEFF was trimmed: %q", page.Items[0].Value)
				}
			}
		}
		page, err = repository.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: field, Query: "\u0085%\u0085"})
		if err != nil || len(page.Items) != 1 {
			t.Fatalf("Go whitespace query %s: %+v %v", field, page, err)
		}
		page, err = repository.List(t.Context(), f.actor, m.DocumentVocabularyInput{Field: field, Query: "i@example.test"})
		if err != nil {
			t.Fatal(err)
		}
		if field == "tag" {
			if len(page.Items) != 1 || page.Items[0].Value != "i@example.test" {
				t.Fatalf("Go-canonical dotted-I tag could not be found with its stored spelling: %+v", page)
			}
		} else if len(page.Items) != 0 {
			t.Fatalf("plain i conflated PostgreSQL dotted-I address identity: %+v", page)
		}
	}
}

func TestVocabularyBoundaryCursorsSurviveRepresentativeDeletion(t *testing.T) {
	for _, boundary := range []string{strings.Repeat("<", 320), strings.Repeat("😀", 320), "Alice@example.test"} {
		t.Run(fmt.Sprintf("%U", []rune(boundary)[0]), func(t *testing.T) {
			f := newIngestionFixture(t)
			repository := vocabularyRepository(t, f)
			id := vocabularyDocument(t, f, f.actor, nil, boundary, nil, nil, nil)
			vocabularyDocument(t, f, f.actor, nil, strings.ToLower(boundary), nil, nil, nil)
			next := strings.Repeat("\U0010ffff", 320)
			vocabularyDocument(t, f, f.actor, nil, next, nil, nil, nil)
			input := m.DocumentVocabularyInput{Field: "sender", Limit: 1}
			page, err := repository.List(t.Context(), f.actor, input)
			if err != nil || len(page.Items) != 1 || page.Items[0].Value != boundary || page.NextCursor == "" {
				t.Fatalf("maximum boundary first page: %+v %v", page, err)
			}
			decoded, err := base64.RawURLEncoding.DecodeString(page.NextCursor)
			if err != nil || len(decoded) > 3072 || len(page.NextCursor) > 4096 {
				t.Fatalf("boundary exceeds cursor envelope: %d/%d, %v", len(decoded), len(page.NextCursor), err)
			}
			key := page.Items[0].Key
			f.exec(t, "DELETE FROM documents WHERE id=$1", id)
			representative, err := repository.List(t.Context(), f.actor, input)
			if err != nil || len(representative.Items) != 1 || representative.Items[0].Key != key || representative.Items[0].Value != strings.ToLower(boundary) {
				t.Fatalf("representative changed opaque identity: %+v %v", representative, err)
			}
			f.exec(t, "DELETE FROM documents WHERE account_id=$1 AND sender=$2", f.actor.AccountID, strings.ToLower(boundary))
			input.Cursor = page.NextCursor
			page, err = repository.List(t.Context(), f.actor, input)
			if err != nil || len(page.Items) != 1 || page.Items[0].Value != next || page.NextCursor != "" {
				t.Fatalf("deleted boundary broke continuation: %+v %v", page, err)
			}
		})
	}
}

func TestVocabularyCursorsBindScopeAndRejectInvalidPositions(t *testing.T) {
	f := newIngestionFixture(t)
	repository := vocabularyRepository(t, f)
	vocabularyDocument(t, f, f.actor, []string{"alpha", "beta"}, "", nil, nil, nil)
	base := m.DocumentVocabularyInput{Field: "tag", Limit: 1}
	page, err := repository.List(t.Context(), f.actor, base)
	if err != nil || page.NextCursor == "" {
		t.Fatalf("cursor fixture: %+v %v", page, err)
	}
	base.Cursor = page.NextCursor
	normalized := base
	normalized.Query = "\u0085"
	if page, err := repository.List(t.Context(), f.actor, normalized); err != nil || len(page.Items) != 1 || page.Items[0].Value != "beta" {
		t.Fatalf("equivalent normalized query rejected its cursor: %+v %v", page, err)
	}
	for _, change := range []func(*m.DocumentVocabularyInput){
		func(input *m.DocumentVocabularyInput) { input.Field = "sender" },
		func(input *m.DocumentVocabularyInput) { input.Query = "alpha" },
		func(input *m.DocumentVocabularyInput) { input.Limit = 2 },
	} {
		input := base
		change(&input)
		if _, err := repository.List(t.Context(), f.actor, input); err == nil {
			t.Fatalf("cursor accepted mismatched input: %+v", input)
		}
	}
	foreign := f.addActor(t)
	if _, err := repository.List(t.Context(), foreign, base); err == nil {
		t.Fatal("foreign namespace accepted cursor")
	}
	body, err := base64.RawURLEncoding.DecodeString(base.Cursor)
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{`{"value":"Alpha"}`, `{"value":" alpha"}`, `{"value":""}`, `{"value":"a\u0000b"}`, `{"value":"\ud800"}`, `{"value":"alpha","extra":1}`, `{"value":"alpha","value":"beta"}`, `{"value":null}`} {
		var envelope map[string]json.RawMessage
		if err := json.Unmarshal(body, &envelope); err != nil {
			t.Fatal(err)
		}
		envelope["key"] = json.RawMessage(key)
		mutated, err := json.Marshal(envelope)
		if err != nil {
			t.Fatal(err)
		}
		input := base
		input.Cursor = base64.RawURLEncoding.EncodeToString(mutated)
		if _, err := repository.List(t.Context(), f.actor, input); err == nil {
			t.Fatalf("invalid cursor position accepted: %s", key)
		}
	}
}

func TestVocabularyRechecksAuthorityBeforeDecodingPosition(t *testing.T) {
	f := newIngestionFixture(t)
	repository := vocabularyRepository(t, f)
	input := m.DocumentVocabularyInput{Field: "tag", Limit: 1, Cursor: "malformed"}
	for _, claim := range []string{"documents:read", "documents:search"} {
		denied := services.NewDocumentVocabularyService(repos.NewDocumentVocabularyRepository(sources.NewDocumentDataSource(f.source.Database())), documentDeniedAuthority{authority: f.authority, claim: claim})
		if _, err := denied.List(t.Context(), f.actor, input); !errors.Is(err, m.ErrForbidden) {
			t.Fatalf("%s must be checked before cursor: %v", claim, err)
		}
	}
	for _, test := range []struct {
		name, change, restore string
		args                  []any
		want                  error
	}{
		{"disabled membership", "UPDATE memberships SET enabled=false WHERE account_id=$1 AND user_id=$2", "UPDATE memberships SET enabled=true WHERE account_id=$1 AND user_id=$2", []any{f.actor.AccountID, f.actor.UserID}, m.ErrUnauthorized},
		{"expired session", "UPDATE sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE digest=$1", "UPDATE sessions SET expires_at=clock_timestamp()+interval '1 hour' WHERE digest=$1", []any{f.actor.SessionDigest}, m.ErrUnauthorized},
		{"credential revision", "UPDATE users SET credential_revision=2 WHERE id=$1", "UPDATE users SET credential_revision=1 WHERE id=$1", []any{f.actor.UserID}, m.ErrUnauthorized},
		{"password restricted", "UPDATE users SET must_change_password=true WHERE id=$1", "UPDATE users SET must_change_password=false WHERE id=$1", []any{f.actor.UserID}, m.ErrPasswordChangeRequired},
	} {
		t.Run(test.name, func(t *testing.T) {
			f.exec(t, test.change, test.args...)
			_, err := repository.List(t.Context(), f.actor, input)
			f.exec(t, test.restore, test.args...)
			if !errors.Is(err, test.want) {
				t.Fatalf("authority must precede cursor: %v", err)
			}
		})
	}
	foreign := f.addActor(t)
	spoofed := f.actor
	spoofed.AccountID = foreign.AccountID
	if _, err := repository.List(t.Context(), spoofed, input); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("system admin accessed foreign library: %v", err)
	}
	spoofed = f.actor
	spoofed.SessionDigest = foreign.SessionDigest
	if _, err := repository.List(t.Context(), spoofed, input); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("foreign session accepted: %v", err)
	}
	f.exec(t, "DELETE FROM sessions WHERE digest=$1", f.actor.SessionDigest)
	if _, err := repository.List(t.Context(), f.actor, input); !errors.Is(err, m.ErrUnauthorized) {
		t.Fatalf("revoked session accepted: %v", err)
	}
}

func TestSearchAddressModesAreIndependentAndBindContinuation(t *testing.T) {
	f := newIngestionFixture(t)
	ids := []string{}
	for index, address := range [][2]string{{"\ufeffAlice@example.test\ufeff", "\ufeffBob@example.test\ufeff"}, {"prefix\ufeffAlice@example.test\ufeff", "\ufeffBob@example.test\ufeff"}, {"\ufeffAlice@example.test\ufeff", "prefix\ufeffBob@example.test\ufeff"}, {"prefix\ufeffAlice@example.test\ufeff", "prefix\ufeffBob@example.test\ufeff"}} {
		doc := f.accept(t, f.actor, fmt.Sprintf("%064x", index+1), fmt.Sprintf("Address %d", index))
		to, cc, bcc := []string{}, []string{}, []string{}
		switch index % 3 {
		case 0:
			to = append(to, address[1])
		case 1:
			cc = append(cc, address[1])
		case 2:
			bcc = append(bcc, address[1])
		}
		f.exec(t, "UPDATE documents SET sender=$2,recipients=$3,cc=$4,bcc=$5 WHERE id=$1", doc.ID, address[0], to, cc, bcc)
		f.ready(t, doc, "address content", unitVector(0))
		ids = append(ids, doc.ID)
	}
	for _, mode := range []string{"fulltext", "semantic"} {
		for _, test := range []struct {
			sender, recipient string
			indexes           []int
		}{{"", "", []int{0, 1, 2, 3}}, {"contains", "contains", []int{0, 1, 2, 3}}, {"exact", "contains", []int{0, 2}}, {"contains", "exact", []int{0, 1}}, {"exact", "exact", []int{0}}} {
			t.Run(mode+"/"+test.sender+"/"+test.recipient, func(t *testing.T) {
				input := m.DocumentSearchInput{Space: m.DefaultConfiguration().EmbeddingSpace(), Mode: mode, Query: "address", Sender: "\ufeffALICE@example.test\ufeff", Recipient: "\ufeffBOB@example.test\ufeff", SenderMatch: test.sender, RecipientMatch: test.recipient, Sort: "title", Limit: 1}
				found := []string{}
				for {
					page, err := f.search(t.Context(), f.actor, input, unitVector(0))
					if err != nil || !searchTotalMatches(mode, page.Total, int64(len(test.indexes))) || len(page.Items) != 1 {
						t.Fatalf("filtered count/page: %+v %v", page, err)
					}
					found = append(found, page.Items[0].Document.ID)
					if page.NextCursor == "" {
						break
					}
					for _, field := range []string{"sender", "recipient"} {
						changed := input
						changed.Cursor = page.NextCursor
						selected := &changed.SenderMatch
						if field == "recipient" {
							selected = &changed.RecipientMatch
						}
						if *selected == "exact" {
							*selected = "contains"
						} else {
							*selected = "exact"
						}
						if _, err := f.search(t.Context(), f.actor, changed, unitVector(0)); err == nil {
							t.Fatalf("%s mode change reused cursor", field)
						}
					}
					input.Cursor = page.NextCursor
					if len(found) > len(test.indexes) {
						t.Fatal("search cursor failed to advance")
					}
				}
				want := []string{}
				for _, index := range test.indexes {
					want = append(want, ids[index])
				}
				if !slices.Equal(found, want) {
					t.Fatalf("address match modes changed rows: got %v, want %v", found, want)
				}
			})
		}
	}
}
