package datasources

import (
	"context"
	"log/slog"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func invoiceInferenceFailure(ctx context.Context, logger *slog.Logger, model, task, reason, code string) error {
	if logger != nil {
		logger.LogAttrs(ctx, slog.LevelWarn, "ai_invoice_validation",
			slog.String("task", task), slog.String("model", model),
			slog.String("outcome", code), slog.String("reason", reason))
	}
	return document.DocumentProcessingError{Code: code}
}
