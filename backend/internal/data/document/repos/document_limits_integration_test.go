//go:build integration

package repos_test

import (
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func TestExpandedDocumentLimitsPersistAndRejectOverflow(t *testing.T) {
	f := newIngestionFixture(t)
	doc := f.accept(t, f.actor, strings.Repeat("e", 64), "Larger original")
	ctx := t.Context()
	for _, table := range []string{"document_uploads", "document_files"} {
		key := "document_id"
		if table == "document_uploads" {
			key = "id"
		}
		f.exec(t, "UPDATE "+table+" SET size=$2 WHERE "+key+"=$1", doc.ID, 100<<20)
		var size int64
		if err := f.connection.QueryRow(ctx, "SELECT size FROM "+table+" WHERE "+key+"=$1", doc.ID).Scan(&size); err != nil || size != 100<<20 {
			t.Fatalf("%s maximum not retained: %d %v", table, size, err)
		}
		if _, err := f.connection.Exec(ctx, "UPDATE "+table+" SET size=$2 WHERE "+key+"=$1", doc.ID, (100<<20)+1); err == nil {
			t.Fatalf("%s accepted file overflow", table)
		}
	}
	text := strings.Repeat("x", 2<<20)
	corrected, err := f.service.CorrectOCR(ctx, f.actor, doc.ID, m.DocumentOCRCorrection{Text: text})
	if err != nil || corrected.Text == nil || *corrected.Text != text {
		t.Fatalf("maximum correction not retained: %v", err)
	}
	var count int
	if err := f.connection.QueryRow(ctx, "SELECT count(*) FROM document_chunks WHERE document_id=$1", doc.ID).Scan(&count); err != nil || count <= 256 {
		t.Fatalf("expanded chunks not retained: count=%d err=%v", count, err)
	}
	for _, column := range []string{"ocr_machine_text", "ocr_manual_text"} {
		f.exec(t, "UPDATE documents SET "+column+"=$2 WHERE id=$1", doc.ID, text)
		if _, err := f.connection.Exec(ctx, "UPDATE documents SET "+column+"=$2 WHERE id=$1", doc.ID, text+"x"); err == nil {
			t.Fatalf("%s accepted text overflow", column)
		}
	}
	f.exec(t, "UPDATE document_chunks SET position=2047 WHERE document_id=$1 AND position=0", doc.ID)
	if _, err := f.connection.Exec(ctx, "UPDATE document_chunks SET position=2048 WHERE document_id=$1 AND position=2047", doc.ID); err == nil {
		t.Fatal("chunk position overflow accepted")
	}
}
