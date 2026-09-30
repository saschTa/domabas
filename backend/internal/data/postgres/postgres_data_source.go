package postgres

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresDataSource struct{ pool *pgxpool.Pool }

func NewPostgresDataSource(ctx context.Context, databaseURL string) (*PostgresDataSource, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database configuration: %w", err)
	}
	config.ConnConfig.ConnectTimeout = 5 * time.Second
	config.MaxConns = 10
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("create database pool: %w", err)
	}
	return &PostgresDataSource{pool: pool}, nil
}

func (source *PostgresDataSource) Close() { source.pool.Close() }

func (source *PostgresDataSource) Ping(ctx context.Context) error { return source.pool.Ping(ctx) }
