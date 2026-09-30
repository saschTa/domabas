package datasources

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
)

func (s *SchedulerDataSource) settingsTx(ctx context.Context, actor m.SchedulerActor, call func(pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SET LOCAL lock_timeout='5s'`); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `SET LOCAL jit=off`); err != nil {
			return err
		}
		if err := schedulerLock(ctx, tx); err != nil {
			return err
		}
		return call(tx)
	})
}

func (s *SchedulerDataSource) settingsReadTx(ctx context.Context, actor m.SchedulerActor, call func(pgx.Tx) error) error {
	return pgx.BeginTxFunc(ctx, s.db, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SET LOCAL jit=off`); err != nil {
			return err
		}
		return call(tx)
	})
}
