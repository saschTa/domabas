//go:build integration

package datasources

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand/v2"
	"strings"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestDocumentVectorIndexPlanRecallAndFilteredCandidates(t *testing.T) {
	databaseURL := testdb.New(t)
	source, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(t.Context())
	account, foreign := uuid.New(), uuid.New()
	if _, err := connection.Exec(t.Context(), "INSERT INTO accounts(id,name) VALUES($1,'Vector recall'),($2,'Foreign vectors')", account, foreign); err != nil {
		t.Fatal(err)
	}
	configuration, _ := json.Marshal(m.DefaultConfiguration())
	space, _ := json.Marshal(m.DefaultConfiguration().EmbeddingSpace())
	random := rand.New(rand.NewPCG(29, 768))
	documents, processing, chunks := [][]any{}, [][]any{}, [][]any{}
	eligible := map[string]int{}
	for index := range 2048 {
		id, owner := uuid.New(), account
		if index >= 1536 {
			owner = foreign
		} else {
			eligible[id.String()] = index
		}
		tags := []string{}
		if index%16 == 0 {
			tags = []string{"selective"}
		}
		documents = append(documents, []any{id, owner, fmt.Sprintf("Vector %04d", index), time.Now(), tags})
		processing = append(processing, []any{id, owner, int64(1), "ready", "complete", int64(1), configuration, time.Now(), false})
		for position := range 16 {
			vector := make([]float64, m.EmbeddingDimensions)
			for dimension := range vector {
				vector[dimension] = random.NormFloat64()
			}
			vector[index%2] += 20 + random.Float64()*20
			vector, err = m.NormalizeVector(vector)
			if err != nil {
				t.Fatal(err)
			}
			chunks = append(chunks, []any{id, owner, int64(1), position, "Vector recall fixture", vector, m.EmbeddingDigest})
		}
	}
	for _, batch := range []struct {
		table   string
		columns []string
		rows    [][]any
	}{
		{"documents", []string{"id", "account_id", "title", "created_at", "tags"}, documents},
		{"document_processing", []string{"document_id", "account_id", "generation", "state", "stage", "configuration_revision", "configuration", "updated_at", "split_pipeline"}, processing},
		{"document_chunks", []string{"document_id", "account_id", "generation", "position", "content", "embedding", "model_digest"}, chunks},
	} {
		if _, err := connection.CopyFrom(t.Context(), pgx.Identifier{batch.table}, batch.columns, pgx.CopyFromRows(batch.rows)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := connection.Exec(t.Context(), "ANALYZE documents; ANALYZE document_processing; ANALYZE document_chunks"); err != nil {
		t.Fatal(err)
	}
	var originalTimeout string
	if err := connection.QueryRow(t.Context(), "SHOW statement_timeout").Scan(&originalTimeout); err != nil {
		t.Fatal(err)
	}
	tx, err := connection.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(t.Context())
	if _, err := tx.Exec(t.Context(), documentSearchTransactionSettings+"; "+documentVectorSearchSettings); err != nil {
		t.Fatal(err)
	}
	var searchTimeout string
	if err := tx.QueryRow(t.Context(), "SHOW statement_timeout").Scan(&searchTimeout); err != nil || searchTimeout != "10s" {
		t.Fatalf("search statement timeout: %q %v", searchTimeout, err)
	}
	indexedPlan := false
	for dimension := range 2 {
		vector := make([]float64, m.EmbeddingDimensions)
		vector[dimension] = 1
		for _, tags := range [][]string{{}, {"selective"}} {
			args := []any{account.String(), tags, "", "", string(space), "contains", "contains", []string{}, vector}
			query := func(indexed bool) string {
				return documentSemanticSearch(indexed) + " SELECT id,score FROM ranked ORDER BY score DESC,id DESC LIMIT 20"
			}
			if _, err := tx.Prepare(t.Context(), "document_indexed_recall", query(true)); err != nil {
				t.Fatal(err)
			}
			read := func(indexed bool) map[string]float64 {
				t.Helper()
				statement := query(indexed)
				if indexed {
					statement = "document_indexed_recall"
				}
				rows, err := tx.Query(t.Context(), statement, args...)
				if err != nil {
					t.Fatal(err)
				}
				defer rows.Close()
				result := map[string]float64{}
				for rows.Next() {
					var id string
					var score float64
					if err := rows.Scan(&id, &score); err != nil {
						t.Fatal(err)
					}
					index, owned := eligible[id]
					if !owned || (len(tags) > 0 && index%16 != 0) {
						t.Fatal("semantic retrieval crossed namespace or tag eligibility")
					}
					result[id] = score
				}
				if err := rows.Err(); err != nil {
					t.Fatal(err)
				}
				return result
			}
			for range 6 {
				read(true)
			}
			exact, indexed := read(false), read(true)
			matched := 0
			for id, score := range indexed {
				if expected, ok := exact[id]; ok {
					matched++
					if math.Abs(expected-score) > 1e-12 {
						t.Fatal("candidate reranking did not use the best eligible chunk")
					}
				}
			}
			recall := float64(matched) / float64(len(exact))
			t.Logf("dimension=%d tags=%v recall@20=%.2f", dimension, tags, recall)
			if len(indexed) != len(exact) || recall < .95 {
				t.Fatalf("insufficient indexed recall: exact=%d indexed=%d matched=%d", len(exact), len(indexed), matched)
			}
			planArgs := append([]any{pgx.QueryExecModeSimpleProtocol}, args...)
			rows, err := tx.Query(t.Context(), "EXPLAIN EXECUTE document_indexed_recall($1,$2,$3,$4,$5,$6,$7,$8,$9)", planArgs...)
			if err != nil {
				t.Fatal(err)
			}
			for rows.Next() {
				var line string
				if err := rows.Scan(&line); err != nil {
					t.Fatal(err)
				}
				if strings.Contains(line, "document_chunks_embedding_cosine_idx") {
					indexedPlan = true
				}
				if strings.Contains(line, "Index Scan") {
					t.Log(line)
				}
			}
			rows.Close()
			if err := rows.Err(); err != nil {
				t.Fatal(err)
			}
		}
	}
	if !indexedPlan {
		t.Fatal("the actual semantic candidate query never selected the HNSW index")
	}
	if err := tx.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	var planning string
	if err := connection.QueryRow(t.Context(), "SHOW plan_cache_mode").Scan(&planning); err != nil || planning != "auto" {
		t.Fatalf("search leaked its plan settings into the connection: %s %v", planning, err)
	}
	if err := connection.QueryRow(t.Context(), "SHOW statement_timeout").Scan(&searchTimeout); err != nil || searchTimeout != originalTimeout {
		t.Fatalf("search leaked its statement timeout into the connection: %q %v", searchTimeout, err)
	}
}
