package datasources

import (
	"encoding/base64"
	"fmt"
	"math"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

const cursorTestID = "00000000-0000-4000-8000-000000000001"

func TestDocumentCursorTypedPositionsAndExactPrecision(t *testing.T) {
	fp := strings.Repeat("a", 64)
	stamp := time.Date(2026, 9, 18, 1, 2, 3, 123456000, time.UTC)
	cases := []struct {
		sort string
		key  documentPosition
	}{
		{"newest", documentPosition{ID: cursorTestID, CreatedAt: stamp}},
		{"oldest", documentPosition{ID: cursorTestID, CreatedAt: stamp}},
		{"title", documentPosition{ID: cursorTestID, Title: strings.Repeat("i\u0307", 200)}},
		{"title", documentPosition{ID: cursorTestID, Title: strings.Repeat("\x01", 200)}},
		{"date-newest", documentPosition{ID: cursorTestID, Date: "2026-09-18"}},
		{"date-oldest", documentPosition{ID: cursorTestID}},
		{"relevance", documentPosition{ID: cursorTestID, Score: math.Nextafter(.5, 1)}},
	}
	for index, tt := range cases {
		t.Run(fmt.Sprintf("%s/%d", tt.sort, index), func(t *testing.T) {
			token, err := encodeDocumentPosition("documents.search", fp, tt.sort, tt.key)
			if err != nil {
				t.Fatal(err)
			}
			got, err := decodeDocumentPosition(token, "documents.search", fp, tt.sort)
			if err != nil {
				t.Fatal(err)
			}
			if got.ID != tt.key.ID || got.Title != tt.key.Title || got.Score != tt.key.Score || !got.CreatedAt.Equal(tt.key.CreatedAt) || got.Date != tt.key.Date {
				t.Fatalf("position lost precision: %+v != %+v", got, tt.key)
			}
		})
	}
}

func TestDocumentCursorRejectsInvalidTypedKeys(t *testing.T) {
	fp := strings.Repeat("a", 64)
	cases := []struct{ name, sort, key string }{
		{"UUID case", "title", `{"id":"ABCDEFAB-0000-4000-8000-000000000001","title":"x"}`},
		{"nil UUID", "title", `{"id":"00000000-0000-0000-0000-000000000000","title":"x"}`},
		{"number score", "relevance", `{"id":"` + cursorTestID + `","score":0.5}`},
		{"noncanonical score", "relevance", `{"id":"` + cursorTestID + `","score":"0.50"}`},
		{"infinite score", "relevance", `{"id":"` + cursorTestID + `","score":"+Inf"}`},
		{"NaN score", "relevance", `{"id":"` + cursorTestID + `","score":"NaN"}`},
		{"timestamp nanos", "newest", `{"id":"` + cursorTestID + `","createdAt":"2026-09-18T01:02:03.123456789Z"}`},
		{"timestamp offset", "newest", `{"id":"` + cursorTestID + `","createdAt":"2026-09-18T01:02:03.123456+00:00"}`},
		{"year zero", "oldest", `{"id":"` + cursorTestID + `","createdAt":"0000-09-18T01:02:03.123456Z"}`},
		{"missing type", "date-newest", `{"id":"` + cursorTestID + `","missing":"true"}`},
		{"missing date extra", "date-oldest", `{"id":"` + cursorTestID + `","missing":true,"date":"2026-09-18"}`},
		{"present missing date", "date-newest", `{"id":"` + cursorTestID + `","missing":false}`},
		{"invalid date", "date-newest", `{"id":"` + cursorTestID + `","missing":false,"date":"2026-02-30"}`},
		{"title NUL", "title", `{"id":"` + cursorTestID + `","title":"a\u0000b"}`},
		{"title oversized", "title", `{"id":"` + cursorTestID + `","title":"` + strings.Repeat("a", 401) + `"}`},
		{"extra key", "title", `{"id":"` + cursorTestID + `","title":"a","extra":1}`},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			token := base64.RawURLEncoding.EncodeToString([]byte(`{"v":1,"op":"documents.search","fp":"` + fp + `","sort":"` + tt.sort + `","key":` + tt.key + `}`))
			if _, err := decodeDocumentPosition(token, "documents.search", fp, tt.sort); err == nil {
				t.Fatal("accepted invalid position")
			}
		})
	}
}

func TestDocumentFingerprintBindsAllCriteriaAndScope(t *testing.T) {
	base := m.DocumentSearchInput{Mode: "fulltext", Query: "invoice", Tags: []string{"a"}, Sender: "sender", Recipient: "recipient", Sort: "title", Limit: 12}
	fp, err := documentCursorFingerprint(cursorTestID, "documents.search", base)
	if err != nil {
		t.Fatal(err)
	}
	changes := []func(*m.DocumentSearchInput){func(i *m.DocumentSearchInput) { i.Mode = "semantic" }, func(i *m.DocumentSearchInput) { i.Query = "other" }, func(i *m.DocumentSearchInput) { i.Tags = []string{"b"} }, func(i *m.DocumentSearchInput) { i.Sender = "other" }, func(i *m.DocumentSearchInput) { i.Recipient = "other" }, func(i *m.DocumentSearchInput) { i.Sort = "newest" }, func(i *m.DocumentSearchInput) { i.Limit++ }}
	for _, change := range changes {
		input := base
		change(&input)
		other, err := documentCursorFingerprint(cursorTestID, "documents.search", input)
		if err != nil || other == fp {
			t.Fatalf("unbound criterion: %+v %v", input, err)
		}
	}
	for _, scope := range []struct{ id, op string }{{"00000000-0000-4000-8000-000000000002", "documents.search"}, {cursorTestID, "documents.list"}} {
		other, err := documentCursorFingerprint(scope.id, scope.op, base)
		if err != nil || other == fp {
			t.Fatal("unbound scope")
		}
	}
	if len(fp) != 64 || len(fp) != len(strings.Repeat("a", 64)) {
		t.Fatal("invalid digest")
	}
	if _, err := pagination.Decode("invalid", "documents.search", fp, "title"); err == nil {
		t.Fatal("malformed base64 accepted")
	}
}
