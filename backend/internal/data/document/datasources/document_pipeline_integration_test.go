//go:build integration

package datasources

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/jackc/pgx/v5"
)

func TestPipelineFingerprintMatchesRetainedSQLSnapshots(t *testing.T) {
	url := testdb.New(t)
	owner, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer owner.Close()
	if err = owner.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	for _, language := range []string{"eng", "deu", "eng+deu"} {
		for _, segmentation := range []string{"auto", "single_block"} {
			c := m.DefaultConfiguration()
			c.Language = language
			c.Segmentation = segmentation
			c.Weights[0], c.Weights[2] = c.Weights[2], c.Weights[0]
			expected, err := c.CanonicalFingerprint()
			if err != nil {
				t.Fatal(err)
			}
			body, _ := json.Marshal(c)
			var actual string
			if err = connection.QueryRow(t.Context(), `SELECT document_pipeline_fingerprint($1::jsonb)`, body).Scan(&actual); err != nil {
				t.Fatal(err)
			}
			if actual != expected {
				t.Fatalf("SQL snapshot identity %s differs from Go %s for %s/%s", actual, expected, language, segmentation)
			}
		}
	}
}
