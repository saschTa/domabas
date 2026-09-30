package datasources

import (
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestSearchContainsFingerprintMatchesCommittedBaseline(t *testing.T) {
	const fingerprint = "b2aa3924bc7fefe61919e26b27842ce35200e12b41c2a8c18b60805b8a68d50c"
	const cursor = "eyJ2IjoxLCJvcCI6ImRvY3VtZW50cy5zZWFyY2giLCJmcCI6ImIyYWEzOTI0YmM3ZmVmZTYxOTE5ZTI2YjI3ODQyY2UzNTIwMGUxMmI0MWMyYThjMThiNjA4MDViOGE2OGQ1MGMiLCJzb3J0IjoidGl0bGUiLCJrZXkiOnsiaWQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJ0aXRsZSI6Imludm9pY2UifX0"
	for _, mode := range []string{"", "contains"} {
		input, err := (m.DocumentSearchInput{Mode: "fulltext", Query: "invoice", Sender: "Alice@example.com", Recipient: "Bob@example.com", SenderMatch: mode, RecipientMatch: mode, Sort: "title", Limit: 12}).Normalize()
		if err != nil {
			t.Fatal(err)
		}
		actual, err := documentCursorFingerprint(cursorTestID, "documents.search", input)
		if err != nil || actual != fingerprint {
			t.Fatalf("contains fingerprint changed from committed baseline: %s %v", actual, err)
		}
		position, err := decodeDocumentPosition(cursor, "documents.search", actual, "title")
		if err != nil || position.Title != "invoice" || position.ID != cursorTestID {
			t.Fatalf("committed baseline cursor no longer accepted: %+v %v", position, err)
		}
		encoded, err := encodeDocumentPosition("documents.search", actual, "title", *position)
		if err != nil || encoded != cursor {
			t.Fatalf("committed cursor encoding changed: %s %v", encoded, err)
		}
	}
}

func TestHybridCursorBindsEmbeddingSpaceAndMode(t *testing.T) {
	input, err := (m.DocumentSearchInput{Mode: "hybrid", Query: "invoice", Space: m.DefaultConfiguration().EmbeddingSpace()}).Normalize()
	if err != nil {
		t.Fatal(err)
	}
	original, err := documentCursorFingerprint(cursorTestID, "documents.search", input)
	if err != nil {
		t.Fatal(err)
	}
	input.Space.IndexingRevision += "-changed"
	changed, err := documentCursorFingerprint(cursorTestID, "documents.search", input)
	if err != nil || original == changed {
		t.Fatalf("hybrid cursor ignored indexing revision: %v", err)
	}
	input.Space = m.DefaultConfiguration().EmbeddingSpace()
	input.Mode = "semantic"
	changed, err = documentCursorFingerprint(cursorTestID, "documents.search", input)
	if err != nil || original == changed {
		t.Fatalf("hybrid cursor reused semantic scores: %v", err)
	}
}

func TestKindCursorCanonicalSelectionAndUnrestrictedCompatibility(t *testing.T) {
	fingerprint := func(kinds []string) string {
		t.Helper()
		input, err := (m.DocumentSearchInput{Mode: "fulltext", Kinds: kinds}).Normalize()
		if err != nil {
			t.Fatal(err)
		}
		value, err := documentCursorFingerprint(cursorTestID, "documents.search", input)
		if err != nil {
			t.Fatal(err)
		}
		return value
	}
	if fingerprint(nil) != fingerprint([]string{"email", "document", "letter"}) {
		t.Fatal("all kinds changed unrestricted cursors")
	}
	selected := fingerprint([]string{"document", "letter"})
	if selected != fingerprint([]string{"letter", "document", "letter"}) {
		t.Fatal("order or duplicates changed effective selection")
	}
	if selected == fingerprint(nil) || selected == fingerprint([]string{"email"}) {
		t.Fatal("cursor did not bind selected kinds")
	}
}
