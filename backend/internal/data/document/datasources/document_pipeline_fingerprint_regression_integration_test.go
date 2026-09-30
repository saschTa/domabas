//go:build integration

package datasources

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/jackc/pgx/v5"
)

func TestIssue12FingerprintCanonicalEscapesAndWeightOrdering(t *testing.T) {
	url := testdb.New(t)
	owner, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer owner.Close()
	if err = owner.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	conn, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(context.Background())
	for _, special := range []string{"plain", `<OCR>&"\\`, "Straße Ελληνικά 日本語", "line\u2028paragraph\u2029", "emoji🧾\t\n"} {
		t.Run(special, func(t *testing.T) {
			c := m.DefaultConfiguration()
			c.Engine = special
			c.EngineVersion = special
			c.EmbeddingModel = special
			c.ExtractionRevision = special
			c.ChunkingRevision = special
			c.EmbeddingInputRevision = special
			c.IndexingRevision = special
			c.Weights = []m.DocumentWeight{{Name: "🧾", SHA256: strings.Repeat("a", 64)}, {Name: "a<&", SHA256: strings.Repeat("b", 64)}, {Name: "Ä", SHA256: strings.Repeat("c", 64)}, {Name: "A", SHA256: strings.Repeat("d", 64)}}
			expected, err := c.CanonicalFingerprint()
			if err != nil {
				t.Fatal(err)
			}
			for _, reverse := range []bool{false, true} {
				if reverse {
					for i, j := 0, len(c.Weights)-1; i < j; i, j = i+1, j-1 {
						c.Weights[i], c.Weights[j] = c.Weights[j], c.Weights[i]
					}
				}
				body, err := json.Marshal(c)
				if err != nil {
					t.Fatal(err)
				}
				var actual string
				if err = conn.QueryRow(t.Context(), `SELECT document_pipeline_fingerprint($1::jsonb)`, body).Scan(&actual); err != nil {
					t.Fatal(err)
				}
				if actual != expected {
					t.Fatalf("SQL and Go differ for escaped/Unicode identity: SQL %s Go %s", actual, expected)
				}
				again, err := c.CanonicalFingerprint()
				if err != nil || again != expected {
					t.Fatalf("weight permutation changed identity: %s %v", again, err)
				}
			}
		})
	}
}
