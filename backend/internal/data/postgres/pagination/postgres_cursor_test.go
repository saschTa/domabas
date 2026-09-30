package pagination

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestCursorEnvelopeRejectsAmbiguousAndNonCanonicalInputs(t *testing.T) {
	fp := strings.Repeat("a", 64)
	body := `{"v":1,"op":"search","fp":"` + fp + `","sort":"title","key":{"id":"record","title":"İ Σ 😀"}}`
	encode := func(s string) string { return base64.RawURLEncoding.EncodeToString([]byte(s)) }
	good := encode(body)
	key, err := Decode(good, "search", fp, "title")
	if err != nil || string(key["title"]) != `"İ Σ 😀"` {
		t.Fatalf("valid Unicode: %v %v", key, err)
	}
	cases := map[string]string{
		"empty": "", "padding": good + "=", "whitespace": good + "\n", "oversized": strings.Repeat("a", MaxEncodedBytes+1),
		"version":            encode(strings.Replace(body, `"v":1`, `"v":2`, 1)),
		"version type":       encode(strings.Replace(body, `"v":1`, `"v":"1"`, 1)),
		"duplicate":          encode(strings.Replace(body, `"v":1`, `"v":1,"v":1`, 1)),
		"escaped duplicate":  encode(strings.Replace(body, `"v":1`, `"v":1,"\u0076":1`, 1)),
		"extra":              encode(strings.Replace(body, `"v":1`, `"v":1,"extra":1`, 1)),
		"missing":            encode(strings.Replace(body, `"v":1,`, "", 1)),
		"null":               encode(strings.Replace(body, `"sort":"title"`, `"sort":null`, 1)),
		"key null":           encode(strings.Replace(body, `"title":"İ Σ 😀"`, `"title":null`, 1)),
		"key duplicate":      encode(strings.Replace(body, `"id":"record"`, `"id":"record","id":"record"`, 1)),
		"key array":          encode(strings.Replace(body, `{"id":"record","title":"İ Σ 😀"}`, `[]`, 1)),
		"surrogate high":     encode(strings.Replace(body, "İ Σ 😀", `\ud800`, 1)),
		"surrogate low":      encode(strings.Replace(body, "İ Σ 😀", `\udc00`, 1)),
		"surrogate mismatch": encode(strings.Replace(body, "İ Σ 😀", `\ud800\u0041`, 1)),
		"invalid utf8":       encode(strings.Replace(body, "İ Σ 😀", string([]byte{0xff}), 1)),
		"trailing JSON":      encode(body + ` {}`),
	}
	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := Decode(token, "search", fp, "title"); !errors.Is(err, ErrInvalidCursor) {
				t.Fatalf("accepted invalid cursor: %v", err)
			}
		})
	}
	for _, mismatch := range []struct{ op, fp, sort string }{{"list", fp, "title"}, {"search", strings.Repeat("b", 64), "title"}, {"search", fp, "newest"}} {
		if _, err := Decode(good, mismatch.op, mismatch.fp, mismatch.sort); !errors.Is(err, ErrInvalidCursor) {
			t.Fatal("cursor reused with changed binding")
		}
	}
	for _, value := range []string{`\ud83d\ude00`, `\\uD800`, `escaped \" quote`} {
		if _, err := Decode(encode(strings.Replace(body, "İ Σ 😀", value, 1)), "search", fp, "title"); err != nil {
			t.Fatalf("rejected valid escape %s: %v", value, err)
		}
	}
}

func TestCursorRoundTripAndEncodingBounds(t *testing.T) {
	fp, err := Fingerprint(struct {
		Scope string
		Limit int
	}{"namespace", 12})
	if err != nil {
		t.Fatal(err)
	}
	token, err := Encode("search", fp, "title", map[string]any{"title": strings.Repeat("\x01", 200), "id": "a"})
	if err != nil {
		t.Fatal(err)
	}
	fields, err := Decode(token, "search", fp, "title")
	if err != nil {
		t.Fatal(err)
	}
	var title string
	if json.Unmarshal(fields["title"], &title) != nil || title != strings.Repeat("\x01", 200) {
		t.Fatal("escaped legacy title changed")
	}
	if _, err := Encode("search", fp, "title", map[string]any{"title": strings.Repeat("\x01", 500)}); !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("oversize encoding: %v", err)
	}
	if _, err := Encode("search", fp, "title", map[string]any{"title": nil}); !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("null key: %v", err)
	}
}

func TestBoundedInvoiceCursorsPreserveLargeKeysAndDefaultLimits(t *testing.T) {
	fp := strings.Repeat("a", 64)
	value := strings.Repeat("<", 4000)
	token, err := EncodeBounded("invoices", fp, "seller_asc", map[string]any{"value": value, "at": "2026-09-29T12:00:00Z", "id": "36c3a63c-c8e1-4c11-a9e4-93986488f2c9"}, 32768)
	if err != nil {
		t.Fatal(err)
	}
	key, err := DecodeBounded(token, "invoices", fp, "seller_asc", 32768)
	var decoded string
	if err != nil || json.Unmarshal(key["value"], &decoded) != nil || decoded != value {
		t.Fatal("long key changed", err)
	}
	if _, err := Decode(token, "invoices", fp, "seller_asc"); !errors.Is(err, ErrInvalidCursor) {
		t.Fatal("default bound widened", err)
	}
	if _, err := EncodeBounded("invoices", fp, "seller_asc", map[string]string{"value": strings.Repeat("<", 6000)}, 32768); !errors.Is(err, ErrInvalidCursor) {
		t.Fatal("invoice bound ignored", err)
	}
}
