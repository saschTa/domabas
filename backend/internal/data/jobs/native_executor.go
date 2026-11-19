package jobs

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/jackc/pgx/v5"
)

type NativeExecutor struct {
	db      *postgres.PostgresDatabase
	address string
	logger  *slog.Logger
	cancel  context.CancelFunc
	done    chan struct{}
	ready   atomic.Bool
	active  map[string]context.CancelFunc
	mu      sync.Mutex
	workers sync.WaitGroup
}
type NativeExecution struct {
	executor           *NativeExecutor
	ID, RunID, Outcome string
	Next, Attempts     int
}

func NewNativeExecutor(db *postgres.PostgresDatabase, address string, logger *slog.Logger) *NativeExecutor {
	return &NativeExecutor{db: db, address: address, logger: logger, done: make(chan struct{}), active: make(map[string]context.CancelFunc)}
}
func (e *NativeExecutor) Start(poll func(context.Context) error) {
	ctx, cancel := context.WithCancel(context.Background())
	e.cancel = cancel
	go func() {
		defer close(e.done)
		for ctx.Err() == nil {
			err := e.session(ctx, poll)
			e.ready.Store(false)
			if ctx.Err() == nil && err != nil {
				e.logger.Error("background executor disconnected", "error", err)
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Second):
			}
		}
	}()
}
func (e *NativeExecutor) session(ctx context.Context, poll func(context.Context) error) error {
	conn, err := pgx.Connect(ctx, e.address)
	if err != nil {
		return err
	}
	defer conn.Close(context.Background())
	probe := time.NewTicker(time.Second)
	defer probe.Stop()
	var leader bool
	for !leader {
		if err = conn.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtextextended(current_database()||'.'||current_schema()||'.domabas.jobs',0))").Scan(&leader); err != nil {
			return err
		}
		if !leader {
			e.ready.Store(true)
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-probe.C:
			}
		}
	}
	var epoch int64
	err = pgx.BeginFunc(ctx, conn, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, "UPDATE scheduler_settings SET executor_epoch=executor_epoch+1 WHERE singleton RETURNING executor_epoch").Scan(&epoch); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, "DELETE FROM scheduler_step_permits")
		return err
	})
	if err != nil {
		return err
	}
	lifetime, cancel := context.WithCancel(context.WithValue(ctx, workerEpochKey{}, epoch))
	discoveryDone := make(chan struct{})
	go func() {
		defer close(discoveryDone)
		for lifetime.Err() == nil {
			if err := poll(lifetime); err != nil && lifetime.Err() == nil {
				e.logger.Warn("background discovery will retry", "error", err)
			}
			select {
			case <-lifetime.Done():
				return
			case <-time.After(time.Second):
			}
		}
	}()
	defer func() { cancel(); <-discoveryDone; e.workers.Wait() }()
	e.ready.Store(true)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-probe.C:
			check, stop := context.WithTimeout(ctx, 3*time.Second)
			err = conn.Ping(check)
			stop()
			if err != nil {
				return err
			}
		}
	}
}

type workerEpochKey struct{}

func WorkerEpoch(ctx context.Context) int64 {
	epoch, _ := ctx.Value(workerEpochKey{}).(int64)
	return epoch
}

func (e *NativeExecutor) Ping() error {
	if !e.ready.Load() {
		return errors.New("background executor is starting or unavailable")
	}
	return nil
}
func (e *NativeExecutor) Close() { e.cancel(); <-e.done }
func (e *NativeExecutor) Execution(ctx context.Context, id string) (NativeExecution, error) {
	r := NativeExecution{executor: e, ID: id}
	err := pgx.BeginFunc(ctx, e.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "INSERT INTO native_executions(workflow_id) VALUES($1) ON CONFLICT DO NOTHING", id); err != nil {
			return err
		}
		return tx.QueryRow(ctx, "SELECT run_id::text,next_step,attempts,outcome FROM native_executions WHERE workflow_id=$1", id).Scan(&r.RunID, &r.Next, &r.Attempts, &r.Outcome)
	})
	return r, err
}
func (e *NativeExecutor) Cancel(id string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	if cancel := e.active[id]; cancel != nil {
		cancel()
		return true
	}
	return false
}
func (r NativeExecution) Start(ctx context.Context, work func(context.Context, *NativeExecution) (string, error)) {
	e := r.executor
	e.mu.Lock()
	defer e.mu.Unlock()
	if _, busy := e.active[r.ID]; busy || r.Outcome != "" {
		return
	}
	ctx, cancel := context.WithCancel(ctx)
	e.active[r.ID] = cancel
	e.workers.Add(1)
	go func() {
		defer e.workers.Done()
		defer func() { cancel(); e.mu.Lock(); delete(e.active, r.ID); e.mu.Unlock() }()
		fresh, err := e.Execution(ctx, r.ID)
		if err != nil || fresh.Outcome != "" {
			return
		}
		r = fresh
		outcome, err := work(ctx, &r)
		if err == nil && ctx.Err() == nil {
			err = pgx.BeginFunc(ctx, e.db, func(tx pgx.Tx) error {
				_, err := tx.Exec(ctx, "UPDATE native_executions SET outcome=$2 WHERE workflow_id=$1 AND outcome='' AND (SELECT executor_epoch FROM scheduler_settings WHERE singleton)=$3", r.ID, outcome, WorkerEpoch(ctx))
				return err
			})
		}
		if err != nil && ctx.Err() == nil {
			e.logger.Warn("background execution will retry", "execution", r.ID, "error", err)
		}
	}()
}
func (r *NativeExecution) Step(ctx context.Context, index int, work func(context.Context, int) error) error {
	if r.Next > index {
		return nil
	}
	if r.Next != index {
		return fmt.Errorf("unexpected job step %d, expected %d", index, r.Next)
	}
	if err := r.executor.db.QueryRow(ctx, "UPDATE native_executions SET attempts=attempts+1 WHERE workflow_id=$1 AND next_step=$2 AND outcome='' AND (SELECT executor_epoch FROM scheduler_settings WHERE singleton)=$3 RETURNING attempts", r.ID, index, WorkerEpoch(ctx)).Scan(&r.Attempts); err != nil {
		return err
	}
	if err := work(ctx, r.Attempts); err != nil {
		return err
	}
	return r.executor.db.QueryRow(ctx, "UPDATE native_executions SET attempts=0,next_step=next_step+1 WHERE workflow_id=$1 AND next_step=$2 AND (SELECT executor_epoch FROM scheduler_settings WHERE singleton)=$3 RETURNING next_step,attempts", r.ID, index, WorkerEpoch(ctx)).Scan(&r.Next, &r.Attempts)
}

// Branch keeps independent retry and completion records for sibling pipelines.
func (r NativeExecution) Branch(ctx context.Context, name string, work func(context.Context, int) (string, error)) (string, error) {
	var outcome string
	var attempts int
	err := pgx.BeginFunc(ctx, r.executor.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "INSERT INTO native_execution_branches(workflow_id,branch) VALUES($1,$2) ON CONFLICT DO NOTHING", r.ID, name); err != nil {
			return err
		}
		return tx.QueryRow(ctx, "UPDATE native_execution_branches SET attempts=attempts+CASE WHEN outcome='' THEN 1 ELSE 0 END WHERE workflow_id=$1 AND branch=$2 AND (SELECT executor_epoch FROM scheduler_settings WHERE singleton)=$3 RETURNING attempts,outcome", r.ID, name, WorkerEpoch(ctx)).Scan(&attempts, &outcome)
	})
	if err != nil || outcome != "" {
		return outcome, err
	}
	outcome, err = work(ctx, attempts)
	if err != nil {
		return "", err
	}
	err = r.executor.db.QueryRow(ctx, "UPDATE native_execution_branches SET outcome=$3 WHERE workflow_id=$1 AND branch=$2 AND attempts=$4 AND (SELECT executor_epoch FROM scheduler_settings WHERE singleton)=$5 RETURNING outcome", r.ID, name, outcome, attempts, WorkerEpoch(ctx)).Scan(&outcome)
	return outcome, err
}
