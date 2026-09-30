package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresDatabase struct{ pool *pgxpool.Pool }

func (source *PostgresDataSource) Database() *PostgresDatabase {
	return &PostgresDatabase{pool: source.pool}
}

func (database *PostgresDatabase) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	return database.pool.QueryRow(ctx, sql, args...)
}
func (database *PostgresDatabase) Begin(ctx context.Context) (pgx.Tx, error) {
	return database.pool.Begin(ctx)
}
func (database *PostgresDatabase) BeginTx(ctx context.Context, options pgx.TxOptions) (pgx.Tx, error) {
	return database.pool.BeginTx(ctx, options)
}
