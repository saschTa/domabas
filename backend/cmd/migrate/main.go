package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/domabas/domabas/backend/internal/config"
	"github.com/domabas/domabas/backend/internal/data/postgres"
)

func main() {
	if err := run(); err != nil {
		slog.Error("migration failed", "error", err)
		os.Exit(1)
	}
	slog.Info("database migrations complete")
}

func run() error {
	config, err := config.Load()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	source, err := postgres.NewPostgresDataSource(ctx, config.DatabaseURL)
	if err != nil {
		return err
	}
	defer source.Close()
	return source.Migrate(ctx)
}
