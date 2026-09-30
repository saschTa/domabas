package temporal

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"go.temporal.io/api/serviceerror"
)

type documentDispatchLogHandler struct {
	slog.Handler
	cancel context.CancelFunc
}

func (h documentDispatchLogHandler) Handle(ctx context.Context, record slog.Record) error {
	err := h.Handler.Handle(ctx, record)
	h.cancel()
	return err
}

func TestDocumentDispatcherLogsSafeFailureDiagnostics(t *testing.T) {
	for _, scenario := range []struct {
		name, code, sqlState string
		failure              error
	}{
		{"Temporal", "Unavailable", "", fmt.Errorf("private wrapper: %w", serviceerror.NewUnavailable("private server details"))},
		{"database", "Unknown", "40P01", &pgconn.PgError{Code: "40P01", Message: "private SQL values", Detail: "private document"}},
		{"deadline", "DeadlineExceeded", "", context.DeadlineExceeded},
	} {
		for _, operation := range []string{"dispatch", "reconcile"} {
			t.Run(scenario.name+"/"+operation, func(t *testing.T) {
				ctx, cancel := context.WithCancel(t.Context())
				defer cancel()
				var output bytes.Buffer
				logger := slog.New(documentDispatchLogHandler{Handler: slog.NewJSONHandler(&output, nil), cancel: cancel})
				dispatcher := NewDocumentIngestionDispatcher(nil, nil, "test-queue", logger)
				dispatcher.workers.Add(1)
				dispatcher.loop(ctx, operation, time.Hour, &atomic.Int64{}, func(context.Context) error { return scenario.failure })
				var record map[string]any
				if err := json.Unmarshal(output.Bytes(), &record); err != nil {
					t.Fatal(err)
				}
				if record["operation"] != operation || record["task_queue"] != "test-queue" || record["error_code"] != scenario.code || record["sql_state"] != scenario.sqlState || record["error_type"] == "" {
					t.Fatalf("missing failure context: %v", record)
				}
				if strings.Contains(output.String(), "private") {
					t.Fatal("dispatcher logged private error contents")
				}
			})
		}
	}
}
