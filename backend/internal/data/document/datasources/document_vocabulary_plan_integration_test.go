//go:build integration

package datasources

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestVocabularyQueryPlansOnDisposableCorpus(t *testing.T) {
	databaseURL := testdb.New(t)
	owner, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer owner.Close()
	if err := owner.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close(context.Background())
	account, foreign := uuid.NewString(), uuid.NewString()
	if _, err := connection.Exec(t.Context(), "INSERT INTO accounts(id,name) VALUES($1,'Vocabulary plan'),($2,'Foreign plan')", account, foreign); err != nil {
		t.Fatal(err)
	}
	if _, err := connection.Exec(t.Context(), `INSERT INTO documents(id,account_id,title,created_at,tags,sender,recipients,cc,bcc)
 SELECT gen_random_uuid(),CASE WHEN n<=500 THEN $1::uuid ELSE $2::uuid END,'Plan fixture',clock_timestamp(),
 ARRAY['shared','tag-'||lpad(n::text,4,'0')],'sender-'||lpad(n::text,4,'0')||'@example.test',
 ARRAY['recipient-'||lpad(n::text,4,'0')||'@example.test'],
 ARRAY['RECIPIENT-'||lpad(n::text,4,'0')||'@example.test'],
 ARRAY['bcc-'||lpad(n::text,4,'0')||'@example.test'] FROM generate_series(1,1000) n`, account, foreign); err != nil {
		t.Fatal(err)
	}
	if _, err := connection.Exec(t.Context(), "ANALYZE documents"); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct{ field, boundary string }{{"tag", "tag-0100"}, {"sender", "sender-0100@example.test"}, {"recipient", "recipient-0100@example.test"}} {
		for _, boundary := range []string{"", test.boundary} {
			var body []byte
			if err := connection.QueryRow(t.Context(), "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) "+vocabularyQuery(test.field), account, "", boundary, 41).Scan(&body); err != nil {
				t.Fatal(err)
			}
			var plans []struct {
				Plan struct {
					Node       string  `json:"Node Type"`
					Rows       float64 `json:"Actual Rows"`
					Hits       int     `json:"Shared Hit Blocks"`
					TempRead   int     `json:"Temp Read Blocks"`
					TempWrites int     `json:"Temp Written Blocks"`
				} `json:"Plan"`
				Time float64 `json:"Execution Time"`
			}
			if err := json.Unmarshal(body, &plans); err != nil || len(plans) != 1 {
				t.Fatalf("invalid PostgreSQL plan: %s %v", body, err)
			}
			plan := plans[0]
			if plan.Plan.Rows != 41 {
				t.Fatalf("%s continuation=%t failed bounded page retrieval: %s", test.field, boundary != "", body)
			}
			t.Logf("%s continuation=%t: %s, %.0f rows, %.3f ms, %d shared hits, %d/%d temporary blocks", test.field, boundary != "", plan.Plan.Node, plan.Plan.Rows, plan.Time, plan.Plan.Hits, plan.Plan.TempRead, plan.Plan.TempWrites)
		}
	}
}
