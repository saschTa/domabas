package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"time"

	identity "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	"github.com/domabas/domabas/backend/internal/config"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/google/uuid"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		slog.Error("administrator bootstrap failed", "error", err)
		os.Exit(1)
	}
}
func run(args []string) error {
	flags := flag.NewFlagSet("bootstrap-admin", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	userID := flags.String("user-id", "", "existing user to become system administrator")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected positional arguments")
	}
	id, err := uuid.Parse(*userID)
	if err != nil || id == uuid.Nil {
		return fmt.Errorf("an explicit valid --user-id UUID is required")
	}
	configuration, err := config.Load()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	database, err := postgres.NewPostgresDataSource(ctx, configuration.DatabaseURL)
	if err != nil {
		return err
	}
	defer database.Close()
	if err := database.Migrate(ctx); err != nil {
		return err
	}
	identities, err := identity.NewIdentityContainer(database.Database(), time.Now)
	if err != nil {
		return err
	}
	if err := identities.Service().BootstrapAdministrator(ctx, id.String()); err != nil {
		return fmt.Errorf("assign first system administrator: %w", err)
	}
	slog.Info("system administrator assigned", "user_id", id.String())
	return nil
}
