//go:build integration

package postgres

import (
	"strings"
	"testing"
	"testing/fstest"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func TestDocumentLimitMigrationPreservesExistingText(t *testing.T) {
	source := migrationSource(t, testdb.New(t))
	files := fstest.MapFS{}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() >= "021" {
			continue
		}
		name := "migrations/" + entry.Name()
		contents, err := migrations.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		files[name] = &fstest.MapFile{Data: contents}
	}
	if err := source.migrate(t.Context(), files); err != nil {
		t.Fatal(err)
	}
	account, document := uuid.New(), uuid.New()
	migrationSQL(t, source, "INSERT INTO accounts(id,name) VALUES($1,'Retained originals')", account)
	migrationSQL(t, source, "INSERT INTO documents(id,account_id,title,description,created_at,ocr_machine_text,ocr_manual_text,ocr_revision) VALUES($1,$2,'Original','',now(),'Machine text','Manual text',7)", document, account)
	large := strings.Repeat("a", 2<<20)
	if _, err := source.pool.Exec(t.Context(), "UPDATE documents SET ocr_machine_text=$2 WHERE id=$1", document, large); err == nil {
		t.Fatal("old schema accepted expanded text before migration")
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	var machine, manual string
	var revision int64
	if err := source.pool.QueryRow(t.Context(), "SELECT ocr_machine_text,ocr_manual_text,ocr_revision FROM documents WHERE id=$1", document).Scan(&machine, &manual, &revision); err != nil || machine != "Machine text" || manual != "Manual text" || revision != 7 {
		t.Fatalf("migration changed retained extraction: %q %q %d %v", machine, manual, revision, err)
	}
	migrationSQL(t, source, "UPDATE documents SET ocr_machine_text=$2,ocr_manual_text=$2 WHERE id=$1", document, large)
}
