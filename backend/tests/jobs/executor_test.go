//go:build jobs

package jobs_test

import (
	"context"
	"errors"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/data/jobs"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/jackc/pgx/v5"
)

func TestStandbyResumesOnlyUnfinishedBranch(t *testing.T) {
	address := testdb.New(t)
	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	source, err := postgres.NewPostgresDataSource(ctx, address)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	if err = source.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	db := source.Database()
	if err = pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "INSERT INTO scheduler_requests(workflow_id,pipeline,state) VALUES('branch-fixture','document_ai','active')")
		return err
	}); err != nil {
		t.Fatal(err)
	}
	var invoices, tags atomic.Int32
	partial := make(chan struct{}, 1)
	finished := make(chan struct{}, 1)
	leader := jobs.NewNativeExecutor(db, address, slog.Default())
	standby := jobs.NewNativeExecutor(db, address, slog.Default())
	poll := func(c context.Context) error {
		r, err := leader.Execution(c, "branch-fixture")
		if err != nil {
			return err
		}
		r.Start(c, func(c context.Context, r *jobs.NativeExecution) (string, error) {
			_, err := r.Branch(c, "invoice", func(context.Context, int) (string, error) { invoices.Add(1); return "done", nil })
			if err != nil {
				return "", err
			}
			_, err = r.Branch(c, "tags", func(c context.Context, _ int) (string, error) {
				tags.Add(1)
				select {
				case partial <- struct{}{}:
				default:
				}
				<-c.Done()
				return "", c.Err()
			})
			return "", err
		})
		return nil
	}
	leader.Start(poll)
	var leaderStopped bool
	defer func() {
		if !leaderStopped {
			leader.Close()
		}
	}()
	select {
	case <-partial:
	case <-ctx.Done():
		t.Fatal("leader did not enter tag branch")
	}
	standby.Start(func(c context.Context) error {
		r, err := standby.Execution(c, "branch-fixture")
		if err != nil {
			return err
		}
		if r.Outcome == "done" {
			select {
			case finished <- struct{}{}:
			default:
			}
			return nil
		}
		r.Start(c, func(c context.Context, r *jobs.NativeExecution) (string, error) {
			_, err := r.Branch(c, "invoice", func(context.Context, int) (string, error) { invoices.Add(1); return "done", nil })
			if err != nil {
				return "", err
			}
			_, err = r.Branch(c, "tags", func(_ context.Context, attempt int) (string, error) {
				if attempt != 2 {
					return "", errors.New("lost retry count")
				}
				tags.Add(1)
				return "done", nil
			})
			return "done", err
		})
		return nil
	})
	defer standby.Close()
	leader.Close()
	leaderStopped = true
	select {
	case <-finished:
	case <-ctx.Done():
		t.Fatal("standby did not finish")
	}
	if invoices.Load() != 1 || tags.Load() != 2 {
		t.Fatal("unexpected branch replay", invoices.Load(), tags.Load())
	}
}
