package temporal

import (
	"context"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"go.temporal.io/sdk/temporal"
)

type DocumentAICompletionService interface {
	Complete(context.Context, document.DocumentJob) error
	Fail(context.Context, document.DocumentJob, string) error
}

type DocumentAIActivities struct {
	ingestion *DocumentIngestionActivities
	service   DocumentAICompletionService
}

func NewDocumentAIActivities(service DocumentAICompletionService, properties DocumentPropertyService, invoices DocumentInvoiceService) *DocumentAIActivities {
	return &DocumentAIActivities{ingestion: NewDocumentIngestionActivities(nil, properties, invoices), service: service}
}
func (a *DocumentAIActivities) Close() { a.ingestion.Close() }
func (a *DocumentAIActivities) Invoice(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	if input.AIAttempt < 1 {
		return temporal.NewNonRetryableApplicationError("invalid AI attempt", "invalid_job", nil)
	}
	return a.ingestion.invoke(ctx, input, a.ingestion.invoices.ExtractInvoice)
}
func (a *DocumentAIActivities) Enrich(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	if input.AIAttempt < 1 {
		return temporal.NewNonRetryableApplicationError("invalid AI attempt", "invalid_job", nil)
	}
	return a.ingestion.invoke(ctx, input, a.ingestion.properties.Enrich)
}
func (a *DocumentAIActivities) Complete(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	if input.AIAttempt < 1 {
		return temporal.NewNonRetryableApplicationError("invalid AI attempt", "invalid_job", nil)
	}
	return a.ingestion.invoke(ctx, input, a.service.Complete)
}
func (a *DocumentAIActivities) Fail(ctx context.Context, input documentworkflows.DocumentIngestionFailure) error {
	if input.Job.AIAttempt < 1 {
		return temporal.NewNonRetryableApplicationError("invalid AI attempt", "invalid_job", nil)
	}
	return a.ingestion.invoke(ctx, input.Job, func(ctx context.Context, j document.DocumentJob) error {
		return a.service.Fail(ctx, j, documentworkflows.DocumentIngestionFailureCode(input.Code))
	})
}
