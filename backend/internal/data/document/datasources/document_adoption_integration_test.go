//go:build integration

package datasources

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestLegacyAdoptionIsExplicitAtomicAndDoesNotMoveOwnedDocuments(t *testing.T) {
	databaseURL := testdb.New(t)
	owner, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(owner.Close)
	if err := owner.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = connection.Close(context.Background()) })
	source := NewDocumentDataSource(owner.Database())
	first, second := uuid.NewString(), uuid.NewString()
	for _, account := range []string{first, second} {
		if _, err := connection.Exec(t.Context(), "INSERT INTO accounts(id,name) VALUES($1,'Adoption account')", account); err != nil {
			t.Fatal(err)
		}
	}
	alreadyOwned := uuid.NewString()
	if _, err := connection.Exec(t.Context(), "INSERT INTO documents(id,account_id,title,created_at) VALUES($1,$2,'Already owned',now())", alreadyOwned, first); err != nil {
		t.Fatal(err)
	}
	if _, err := connection.Exec(t.Context(), "INSERT INTO documents(id,title,created_at) SELECT gen_random_uuid(),'legacy',now() FROM generate_series(1,5)"); err != nil {
		t.Fatal(err)
	}
	if _, err := source.AdoptLegacyDocuments(t.Context(), uuid.NewString()); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("invalid target: %v", err)
	}
	start := make(chan struct{})
	results := make(chan int64, 2)
	var wg sync.WaitGroup
	for _, account := range []string{first, second} {
		wg.Go(func() {
			<-start
			n, err := source.AdoptLegacyDocuments(t.Context(), account)
			if err != nil {
				t.Error(err)
			}
			results <- n
		})
	}
	close(start)
	wg.Wait()
	a, b := <-results, <-results
	if a+b != 5 || a != 0 && b != 0 {
		t.Fatalf("concurrent adoption moved records: %d %d", a, b)
	}
	if n, err := source.AdoptLegacyDocuments(t.Context(), first); err != nil || n != 0 {
		t.Fatalf("repeat adoption: %d %v", n, err)
	}
	var owned int
	if err := connection.QueryRow(t.Context(), "SELECT count(*) FROM documents WHERE account_id IS NOT NULL").Scan(&owned); err != nil || owned != 6 {
		t.Fatalf("retained docs %d %v", owned, err)
	}
	var retained string
	if err := connection.QueryRow(t.Context(), "SELECT account_id FROM documents WHERE id=$1", alreadyOwned).Scan(&retained); err != nil || retained != first {
		t.Fatalf("already-owned document moved: %s %v", retained, err)
	}
}

func TestLegacyAdoptionWaitsForAcceptanceBeforeLockingAccount(t *testing.T) {
	databaseURL := testdb.New(t)
	owner, err := postgres.NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(owner.Close)
	if err := owner.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	connection, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = connection.Close(context.Background()) })
	account := uuid.NewString()
	if _, err := connection.Exec(t.Context(), "INSERT INTO accounts(id,name) VALUES($1,'Concurrent adoption')", account); err != nil {
		t.Fatal(err)
	}
	if _, err := connection.Exec(t.Context(), "INSERT INTO documents(id,title,created_at) VALUES(gen_random_uuid(),'Legacy document',clock_timestamp())"); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	holder, err := connection.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(context.Background())
	if _, err := holder.Exec(ctx, `SELECT pg_advisory_xact_lock_shared(hashtextextended(current_database()||':'||current_schema()||':document-processing',0))`); err != nil {
		t.Fatal(err)
	}
	source := NewDocumentDataSource(owner.Database())
	type adoptionResult struct {
		count int64
		err   error
	}
	done := make(chan adoptionResult, 1)
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		count, err := source.AdoptLegacyDocuments(ctx, account)
		done <- adoptionResult{count: count, err: err}
	}()
	t.Cleanup(func() {
		cancel()
		_ = holder.Rollback(context.Background())
		<-finished
	})
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		var waiting bool
		if err := owner.Database().QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND mode='ExclusiveLock' AND NOT granted AND $1::integer=ANY(pg_blocking_pids(pid)))`, int(connection.PgConn().PID())).Scan(&waiting); err != nil {
			t.Fatal(err)
		}
		if waiting {
			break
		}
		select {
		case result := <-done:
			t.Fatalf("adoption bypassed held acceptance barrier: %+v", result)
		case <-ctx.Done():
			t.Fatal("adoption never waited for acceptance barrier")
		case <-ticker.C:
		}
	}
	insertCtx, stopInsert := context.WithTimeout(ctx, time.Second)
	defer stopInsert()
	if _, err := holder.Exec(insertCtx, "INSERT INTO documents(id,account_id,title,created_at) VALUES($1,$2,'Concurrent creator',clock_timestamp())", uuid.NewString(), account); err != nil {
		t.Fatalf("adoption held account before acceptance barrier: %v", err)
	}
	if err := holder.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	result := <-done
	if result.err != nil || result.count != 1 {
		t.Fatalf("adoption after acceptance: %+v", result)
	}
}
