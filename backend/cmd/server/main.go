package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/domabas/domabas/backend/internal/bootstrap"
	"github.com/domabas/domabas/backend/internal/config"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	config, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	startupCtx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	app, err := bootstrap.NewBackendApp(startupCtx, config, logger)
	cancel()
	if err != nil {
		return err
	}
	defer app.Close()
	listener, err := net.Listen("tcp", config.HTTPAddress)
	if err != nil {
		return err
	}
	server := &http.Server{Handler: app.Handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 130 * time.Second, WriteTimeout: 130 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 1 << 20}
	result := make(chan error, 1)
	go func() { result <- server.Serve(listener) }()
	logger.Info("server listening", "address", listener.Addr().String())
	var cause error
	select {
	case err := <-result:
		if !errors.Is(err, http.ErrServerClosed) {
			cause = err
		}
	case err := <-app.FatalErrors():
		cause = fmt.Errorf("Temporal worker failed: %w", err)
	case <-ctx.Done():
	}
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	app.DrainRealtime()
	if err := server.Shutdown(shutdownCtx); err != nil {
		_ = server.Close()
		return errors.Join(cause, err)
	}
	return cause
}
