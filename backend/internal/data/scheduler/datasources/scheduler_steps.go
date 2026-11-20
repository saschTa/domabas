package datasources

import (
	"context"
	"errors"
	"time"

	"github.com/domabas/domabas/backend/internal/data/jobs"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// RunStep acquires all stage and provider slots together. The native executor drains
// calls before releasing its leadership session, including during shutdown.
func (s *SchedulerDataSource) RunStep(ctx context.Context, id, stage string, work func(context.Context) error) error {
	if stage == "stage:embedding" {
		return s.RunResources(ctx, id, stage, []string{stage, "embedding-runtime"}, work)
	}
	return s.RunResources(ctx, id, stage, []string{stage}, work)
}

func (s *SchedulerDataSource) RunResources(ctx context.Context, id, scope string, resources []string, work func(context.Context) error) error {
	token := uuid.NewString()
	for {
		acquired := false
		err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
			if err := schedulerLock(ctx, tx); err != nil {
				return err
			}
			if epoch := jobs.WorkerEpoch(ctx); epoch != 0 {
				var current int64
				if err := tx.QueryRow(ctx, "SELECT executor_epoch FROM scheduler_settings WHERE singleton").Scan(&current); err != nil {
					return err
				}
				if epoch != current {
					return errors.New("worker leadership changed")
				}
			}
			if _, err := tx.Exec(ctx, "DELETE FROM scheduler_step_permits WHERE workflow_id=$1 AND scope=$2", id, scope); err != nil {
				return err
			}
			return tx.QueryRow(ctx, `WITH wanted AS (
 SELECT DISTINCT id FROM unnest($2::text[]) id WHERE id<>''
 ), fits AS (SELECT NOT EXISTS(SELECT 1 FROM wanted w JOIN scheduler_resources r USING(id)
 WHERE (SELECT count(*) FROM scheduler_step_permits p WHERE p.resource_id=w.id)>=r.concurrency_limit) AS available),
 grant_slots AS (INSERT INTO scheduler_step_permits SELECT $1,id,$3,$4 FROM wanted, fits WHERE available)
 SELECT available FROM fits`, id, resources, scope, token).Scan(&acquired)
		})
		if err != nil {
			return err
		}
		if acquired {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(250 * time.Millisecond):
		}
	}
	err := work(ctx)
	cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	releaseErr := pgx.BeginFunc(cleanup, s.db, func(tx pgx.Tx) error {
		_, err := tx.Exec(cleanup, "DELETE FROM scheduler_step_permits WHERE workflow_id=$1 AND token=$2", id, token)
		return err
	})
	if releaseErr != nil {
		return releaseErr
	}
	return err
}
