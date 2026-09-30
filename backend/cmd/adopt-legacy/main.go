package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/domabas/domabas/backend/internal/config"
	documentsources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/google/uuid"
)

func main() {
	account := flag.String("account-id", "", "existing account that receives unassigned legacy documents")
	flag.Parse()
	if err := run(*account); err != nil {
		slog.Error("legacy document adoption failed", "error", err)
		os.Exit(1)
	}
}
func run(account string) error {
	if _, err := uuid.Parse(account); err != nil {
		return fmt.Errorf("a valid --account-id is required: %w", err)
	}
	configuration, err := config.Load()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	source, err := postgres.NewPostgresDataSource(ctx, configuration.DatabaseURL)
	if err != nil {
		return err
	}
	defer source.Close()
	if err := source.Migrate(ctx); err != nil {
		return err
	}
	count, err := documentsources.NewDocumentDataSource(source.Database()).AdoptLegacyDocuments(ctx, account)
	if err != nil {
		return err
	}
	slog.Info("legacy document adoption complete", "account_id", account, "documents", count)
	return nil
}
