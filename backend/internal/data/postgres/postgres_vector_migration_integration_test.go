//go:build integration

package postgres

import (
	"strings"
	"testing"
	"testing/fstest"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func TestVectorIndexMigrationPreservesExistingEmbeddingsAndRetries(t *testing.T) {
	source := migrationSource(t, testdb.New(t))
	files := fstest.MapFS{}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() >= "029" {
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
	migrationSQL(t, source, "INSERT INTO accounts(id,name) VALUES($1,'Retained vector test')", account)
	migrationSQL(t, source, "INSERT INTO documents(id,account_id,title,created_at) VALUES($1,$2,'Retained embeddings',now())", document, account)
	vector := make([]float64, 768)
	vector[0], vector[1] = 0.6000000000000001, 0.8
	digest := strings.Repeat("a", 64)
	migrationSQL(t, source, "INSERT INTO document_chunks(document_id,account_id,generation,position,content,embedding,model_digest) VALUES($1,$2,1,0,'retained original',$3,$4),($1,$2,2,0,'pending embedding',NULL,NULL)", document, account, vector, digest)
	read := func() string {
		t.Helper()
		var value string
		if err := source.pool.QueryRow(t.Context(), `SELECT string_agg(generation::text || ':' || position::text || ':' || content || ':' || COALESCE(encode(array_send(embedding),'hex'),'null') || ':' || COALESCE(model_digest,'null'),';' ORDER BY generation,position) FROM document_chunks WHERE document_id=$1`, document).Scan(&value); err != nil {
			t.Fatal(err)
		}
		return value
	}
	original := read()
	invalid := make([]float64, 768)
	invalid[0] = 1e300
	migrationSQL(t, source, "INSERT INTO document_chunks(document_id,account_id,generation,position,content,embedding,model_digest) VALUES($1,$2,3,0,'invalid legacy magnitude',$3,$4)", document, account, invalid, digest)
	if err := source.Migrate(t.Context()); err == nil {
		t.Fatal("out-of-range legacy vector must fail atomically rather than be discarded")
	}
	var applied, indexExists bool
	if err := source.pool.QueryRow(t.Context(), `SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='029_document_vector_index.sql'),to_regclass('document_chunks_embedding_cosine_idx') IS NOT NULL`).Scan(&applied, &indexExists); err != nil {
		t.Fatal(err)
	}
	if applied || indexExists {
		t.Fatal("failed index build left a migration or invalid index behind")
	}
	migrationSQL(t, source, "DELETE FROM document_chunks WHERE document_id=$1 AND generation=3", document)
	for range 2 {
		if err := source.Migrate(t.Context()); err != nil {
			t.Fatal(err)
		}
		if read() != original {
			t.Fatal("migration changed existing embedding bytes, text, model digest or generation")
		}
	}
	var valid bool
	if err := source.pool.QueryRow(t.Context(), `SELECT indisvalid FROM pg_index WHERE indexrelid='document_chunks_embedding_cosine_idx'::regclass`).Scan(&valid); err != nil || !valid {
		t.Fatalf("vector index is not valid: %v", err)
	}
	migrationSQL(t, source, "UPDATE document_chunks SET embedding=$2,model_digest=$3 WHERE document_id=$1 AND generation=2", document, vector, digest)
	var count int
	if err := source.pool.QueryRow(t.Context(), `SELECT count(*) FROM document_chunks WHERE document_id=$1 AND embedding IS NOT NULL AND (embedding::public.vector(768) OPERATOR(public.<=>) $2::float8[]::public.vector(768))<0.00001`, document, vector).Scan(&count); err != nil || count != 2 {
		t.Fatalf("pending embedding did not become searchable: count=%d err=%v", count, err)
	}
}
