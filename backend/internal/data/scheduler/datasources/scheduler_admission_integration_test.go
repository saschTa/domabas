//go:build integration

package datasources

import (
	"context"
	"fmt"
	schedulerservices "github.com/domabas/domabas/backend/internal/domain/scheduler/services"
	"sync"
	"testing"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type schedulerAdmissionFixture struct {
	t          *testing.T
	database   *postgres.PostgresDataSource
	connection *pgx.Conn
	source     *SchedulerDataSource
	service    *schedulerservices.SchedulerService
}

func newSchedulerAdmissionFixture(t *testing.T) *schedulerAdmissionFixture {
	t.Helper()
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
	source := NewSchedulerDataSource(database.Database(), 128)
	if err = source.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	return &schedulerAdmissionFixture{t: t, database: database, connection: connection, source: source}
}

func (f *schedulerAdmissionFixture) exec(query string, args ...any) {
	f.t.Helper()
	if _, err := f.connection.Exec(f.t.Context(), query, args...); err != nil {
		f.t.Fatal(err)
	}
}

func (f *schedulerAdmissionFixture) paperless() string {
	f.t.Helper()
	id := uuid.NewString()
	account, owner := uuid.NewString(), uuid.NewString()
	f.exec("BEGIN")
	f.exec(`INSERT INTO accounts(id,name) VALUES($1,'Scheduler queued workload')`, account)
	f.exec(`INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,$2,'unused',$3)`, owner, owner+"@example.test", account)
	f.exec(`INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)`, account, owner)
	f.exec("COMMIT")
	f.exec(`INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue) VALUES($1,$2,$3,1,'https://paperless.example.test','test-only','scheduler-admission')`, id, account, owner)
	return "domabas-paperless-" + id
}

func (f *schedulerAdmissionFixture) reserve(id string, providers ...string) bool {
	f.t.Helper()
	var admitted bool
	if err := pgx.BeginFunc(f.t.Context(), f.database.Database(), func(tx pgx.Tx) error {
		var err error
		admitted, err = f.source.Reserve(f.t.Context(), tx, id, "paperless", providers)
		if err != nil || !admitted {
			return err
		}
		_, err = tx.Exec(f.t.Context(), `UPDATE paperless_runs SET first_start_at=COALESCE(first_start_at,clock_timestamp()) WHERE 'domabas-paperless-'||id::text=$1`, id)
		return err
	}); err != nil {
		f.t.Fatal(err)
	}
	return admitted
}

func (f *schedulerAdmissionFixture) close(id string) {
	f.t.Helper()
	f.exec(`UPDATE paperless_runs SET execution_closed=true,state='succeeded',stage='complete' WHERE 'domabas-paperless-'||id::text=$1`, id)
}

func (f *schedulerAdmissionFixture) active(resource string) int {
	f.t.Helper()
	var count int
	if err := f.connection.QueryRow(f.t.Context(), `SELECT count(*) FROM scheduler_requests q JOIN scheduler_request_resources r ON r.workflow_id=q.workflow_id WHERE q.state='active' AND r.resource_id=$1`, resource).Scan(&count); err != nil {
		f.t.Fatal(err)
	}
	return count
}

func (f *schedulerAdmissionFixture) feasible(workflowID string) bool {
	f.t.Helper()
	var feasible bool
	if err := f.connection.QueryRow(f.t.Context(), `SELECT feasible FROM scheduler_waiting_requests WHERE workflow_id=$1`, workflowID).Scan(&feasible); err != nil {
		f.t.Fatal(err)
	}
	return feasible
}

func TestSchedulerAdmitsOldestFeasibleWithoutPartialReservations(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	f.exec(`UPDATE scheduler_resources SET concurrency_limit=2 WHERE id='worker'`)
	running, older, bypass, younger := f.paperless(), f.paperless(), f.paperless(), f.paperless()
	if !f.reserve(running, "embedding-runtime") {
		t.Fatal("initial model job not admitted")
	}
	if !f.reserve(bypass, "embedding-runtime") || f.active("embedding-runtime") != 0 {
		t.Fatal("provider capacity was charged during admission")
	}
	if f.reserve(older) || f.reserve(younger) || f.feasible(older) {
		t.Fatal("worker budget exceeded")
	}
	f.close(running)
	if f.reserve(younger) || !f.feasible(older) {
		t.Fatal("younger job bypassed an older feasible request")
	}
	if !f.reserve(older) || f.active("worker") != 2 {
		t.Fatal("oldest job did not claim freed capacity")
	}
	f.close(bypass)
	if !f.reserve(younger) {
		t.Fatal("waiting job did not progress")
	}

}

func TestSchedulerResourceDecreaseAndCancellationKeepRunningOwner(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	f.exec(`UPDATE scheduler_resources SET concurrency_limit=2 WHERE id='pipeline:paperless'`)
	first, second, waiting := f.paperless(), f.paperless(), f.paperless()
	if !f.reserve(first, "embedding-runtime") || !f.reserve(second, "embedding-runtime") {
		t.Fatal("initial jobs not admitted")
	}
	f.exec(`UPDATE scheduler_resources SET concurrency_limit=1 WHERE id='pipeline:paperless'`)
	f.exec(`UPDATE paperless_runs SET state='cancelled',cancel_requested=true WHERE 'domabas-paperless-'||id::text=$1`, first)
	if f.reserve(waiting, "embedding-runtime") || f.active("pipeline:paperless") != 2 {
		t.Fatal("lowered limit or visible cancellation released running reservation")
	}
	if !f.reserve(second, "embedding-runtime") {
		t.Fatal("existing delivery blocked by capacity reduction")
	}
	f.close(first)
	if f.reserve(waiting, "embedding-runtime") {
		t.Fatal("new job admitted while drain still equals lowered limit")
	}
	f.close(second)
	if !f.reserve(waiting, "embedding-runtime") {
		t.Fatal("new job not admitted after owners closed")
	}
}

func TestSchedulerConcurrentReplicasShareAllPipelineBudgets(t *testing.T) {
	f := newSchedulerAdmissionFixture(t)
	f.exec(`UPDATE scheduler_resources SET concurrency_limit=5 WHERE id='worker'`)
	f.exec(`UPDATE scheduler_resources SET concurrency_limit=3 WHERE id='embedding-runtime'`)
	second := NewSchedulerDataSource(f.database.Database(), 128)
	if err := second.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	start := make(chan struct{})
	errors := make(chan error, 40)
	var group sync.WaitGroup
	for index := range 40 {
		group.Add(1)
		go func() {
			defer group.Done()
			<-start
			source := f.source
			if index%2 == 0 {
				source = second
			}
			pipeline := []string{"document_ingestion", "document_ai", "chat", "email", "paperless"}[index%5]
			var providers []string
			if index%5 < 3 {
				providers = []string{"embedding-runtime"}
			}
			err := pgx.BeginFunc(t.Context(), f.database.Database(), func(tx pgx.Tx) error {
				_, err := source.Reserve(t.Context(), tx, fmt.Sprintf("concurrent-%d", index), pipeline, providers)
				return err
			})
			if err != nil {
				errors <- err
			}
		}()
	}
	close(start)
	group.Wait()
	close(errors)
	for err := range errors {
		t.Error(err)
	}
	if got := f.active("worker"); got != 5 {
		t.Fatalf("worker admissions %d, want5", got)
	}
	if got := f.active("embedding-runtime"); got > 3 {
		t.Fatalf("shared model admissions %d exceed3", got)
	}
	if err := second.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	if got := f.active("worker"); got != 5 {
		t.Fatalf("restart lost unverifiable active owners: %d", got)
	}
}
