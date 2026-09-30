//go:build integration

package datasources

import (
	"context"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestSchedulerRetainedMissingSnapshotBlocksNewWorkWithoutBlockingStartup(t *testing.T) {
	url := testdb.New(t)
	database, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(database.Close)
	if err = database.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { connection.Close(context.Background()) })
	account, document := uuid.NewString(), uuid.NewString()
	workflowID := "document-ingestion-v1/" + account + "/" + document + "/1"
	if _, err = connection.Exec(t.Context(), `INSERT INTO document_processing_executions(account_id,document_id,generation,workflow_id,admitted_at,delivery_deadline,legacy) VALUES($1,$2,1,$3,clock_timestamp(),clock_timestamp()+interval '1 hour',true)`, account, document, workflowID); err != nil {
		t.Fatal(err)
	}
	source := NewSchedulerDataSource(database.Database(), 128, "http://ollama.test:11434")
	if err = source.Initialize(t.Context()); err != nil {
		t.Fatalf("unknown retained provider prevented recovery startup: %v", err)
	}
	reserve := func(id, pipeline string, providers []string) bool {
		t.Helper()
		var admitted bool
		if err := pgx.BeginFunc(t.Context(), database.Database(), func(tx pgx.Tx) error {
			var err error
			admitted, err = source.Reserve(t.Context(), tx, id, pipeline, providers)
			return err
		}); err != nil {
			t.Fatal(err)
		}
		return admitted
	}
	if reserve("domabas-paperless-"+uuid.NewString(), "paperless", nil) {
		t.Fatal("unknown retained workload did not block new admission")
	}
	if !reserve(workflowID, "document_ingestion", []string{"ollama", "https://legacy-provider.test/v1"}) {
		t.Fatal("retained delivery or reconciliation was blocked")
	}
	if err = source.Initialize(t.Context()); err != nil {
		t.Fatal("restart while retaining unknown workload", err)
	}
	var state string
	var blocks bool
	if err = connection.QueryRow(t.Context(), `SELECT state,blocks_admission FROM scheduler_requests WHERE workflow_id=$1`, workflowID).Scan(&state, &blocks); err != nil || state != "active" || !blocks {
		t.Fatal(state, blocks, err)
	}
	if _, err = connection.Exec(t.Context(), `UPDATE document_processing_executions SET closed_at=clock_timestamp() WHERE workflow_id=$1`, workflowID); err != nil {
		t.Fatal(err)
	}
	if !reserve("domabas-paperless-"+uuid.NewString(), "paperless", nil) {
		t.Fatal("proven closure did not release admission barrier")
	}
	if err = connection.QueryRow(t.Context(), `SELECT state FROM scheduler_requests WHERE workflow_id=$1`, workflowID).Scan(&state); err != nil || state != "released" {
		t.Fatal(state, err)
	}
}
