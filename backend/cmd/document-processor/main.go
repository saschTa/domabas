package main

import (
	"context"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/domabas/domabas/backend/internal/bootstrap/document"
)

func listenAddress(value string) (string, error) {
	if value == "" {
		return ":8091", nil
	}
	host, port, err := net.SplitHostPort(value)
	if err != nil || strings.ContainsAny(host, " \t\r\n/\\") {
		return "", errors.New("HTTP_ADDR must be a host:port address")
	}
	number, err := strconv.ParseUint(port, 10, 16)
	if err != nil || number == 0 {
		return "", errors.New("HTTP_ADDR port must be between 1 and 65535")
	}
	return value, nil
}

func embeddingQueueCapacity(value string) (int, error) {
	if value == "" {
		value = "128"
	}
	capacity, err := strconv.Atoi(value)
	if err != nil || capacity < 1 {
		return 0, errors.New("EMBEDDING_QUEUE_SIZE must be a positive integer")
	}
	return capacity, nil
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if len(os.Args) > 1 && os.Args[1] == "worker" {
		return document.RunProcessorWorker(ctx, os.Args[2:], os.Stdin, os.Stdout)
	}
	address, err := listenAddress(os.Getenv("HTTP_ADDR"))
	if err != nil {
		return err
	}
	queueCapacity, err := embeddingQueueCapacity(os.Getenv("EMBEDDING_QUEUE_SIZE"))
	if err != nil {
		return err
	}
	config := document.DocumentProcessorConfig{ModelCacheRoot: os.Getenv("MODEL_CACHE_ROOT"), EmbeddingModelPath: os.Getenv("EMBEDDING_MODEL_PATH"), EmbeddingURL: os.Getenv("EMBEDDING_URL"), EmbeddingQueueSize: queueCapacity}
	if config.ModelCacheRoot == "" || config.EmbeddingModelPath == "" || config.EmbeddingURL == "" {
		return errors.New("MODEL_CACHE_ROOT, EMBEDDING_MODEL_PATH and EMBEDDING_URL are required")
	}
	container, err := document.NewDocumentProcessorContainer(ctx, config)
	if err != nil {
		return err
	}
	defer container.Close()
	server := &http.Server{Addr: address, Handler: container.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 490 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8 << 10, BaseContext: nil}
	stopped := make(chan error, 1)
	go func() { stopped <- server.ListenAndServe() }()
	select {
	case err = <-stopped:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
	}
	drain, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err = server.Shutdown(drain); err != nil {
		_ = server.Close()
	}
	return nil
}
func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
