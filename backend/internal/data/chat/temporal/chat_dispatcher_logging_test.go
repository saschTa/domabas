package temporal

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	"go.temporal.io/api/serviceerror"
)

type chatDispatchLogHandler struct {
	slog.Handler
	cancel context.CancelFunc
}

func (h chatDispatchLogHandler) Handle(ctx context.Context, record slog.Record) error {
	err := h.Handler.Handle(ctx, record)
	h.cancel()
	return err
}

func TestChatDispatcherLogsSafeFailureDiagnostics(t *testing.T) {
	for _, scenario := range []struct {
		name, code, sqlState string
		failure              error
	}{
		{"Temporal", "Unavailable", "", fmt.Errorf("private wrapper: %w", serviceerror.NewUnavailable("private server details"))},
		{"database", "Unknown", "40P01", &pgconn.PgError{Code: "40P01", Message: "private SQL values", Detail: "private document"}},
		{"deadline", "DeadlineExceeded", "", context.DeadlineExceeded},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			var output bytes.Buffer
			logger := slog.New(chatDispatchLogHandler{Handler: slog.NewJSONHandler(&output, nil), cancel: cancel})
			dispatcher := NewChatDispatcher(nil, nil, "test-chat", logger, func(context.Context) error { return scenario.failure })
			dispatcher.active.Add(1)
			dispatcher.loop(ctx)
			var record map[string]any
			if err := json.Unmarshal(output.Bytes(), &record); err != nil {
				t.Fatal(err)
			}
			if record["task_queue"] != "test-chat" || record["error_code"] != scenario.code || record["sql_state"] != scenario.sqlState || record["error_type"] == "" {
				t.Fatalf("missing failure context: %v", record)
			}
			if strings.Contains(output.String(), "private") {
				t.Fatal("dispatcher logged private error contents")
			}
		})
	}
}
