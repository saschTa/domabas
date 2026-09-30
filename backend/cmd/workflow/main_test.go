package main

import (
	"context"
	"io"
	"log/slog"
	"testing"
)

func TestInvalidDiagnosticsFailBeforeConnecting(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	for _, args := range [][]string{
		{}, {"--document-id", "invalid"}, {"--timeout", "0s"},
		{"--wait-workflow-id", "existing", "--enqueue-only"},
		{"--wait-workflow-id", "existing", "--workflow-id", "new"},
		{"--document-id", "b25f9c51-87c5-48b1-8460-65ea11babc99", "--run-id", "run"},
	} {
		if err := run(context.Background(), args, io.Discard, logger); err == nil {
			t.Errorf("invalid flags accepted: %v", args)
		}
	}
}
