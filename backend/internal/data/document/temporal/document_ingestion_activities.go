package temporal

import (
	"context"
	"errors"
	"sync"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/google/uuid"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
)

type DocumentIngestionService interface {
	Extract(context.Context, document.DocumentJob) error
	Embed(context.Context, document.DocumentJob) error
	Finalize(context.Context, document.DocumentJob) error
	Fail(context.Context, document.DocumentJob, string) error
}

type DocumentPropertyService interface {
	Enrich(context.Context, document.DocumentJob) error
}

type DocumentInvoiceService interface {
	ExtractInvoice(context.Context, document.DocumentJob) error
}

type DocumentIngestionActivities struct {
	invoices   DocumentInvoiceService
	properties DocumentPropertyService
	service    DocumentIngestionService
	mu         sync.Mutex
	closing    bool
	active     sync.WaitGroup
	lifetime   context.Context
	cancel     context.CancelFunc
}

func NewDocumentIngestionActivities(service DocumentIngestionService, properties DocumentPropertyService, invoices DocumentInvoiceService) *DocumentIngestionActivities {
	lifetime, cancel := context.WithCancel(context.Background())
	return &DocumentIngestionActivities{invoices: invoices, service: service, properties: properties, lifetime: lifetime, cancel: cancel}
}

func (activities *DocumentIngestionActivities) Close() {
	activities.mu.Lock()
	activities.closing = true
	activities.cancel()
	activities.mu.Unlock()
	activities.active.Wait()
}

func (activities *DocumentIngestionActivities) Extract(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	return activities.invoke(ctx, input, activities.service.Extract)
}

func (activities *DocumentIngestionActivities) Enrich(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	return activities.invoke(ctx, input, activities.properties.Enrich)
}

func (activities *DocumentIngestionActivities) Invoice(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	return activities.invoke(ctx, input, activities.invoices.ExtractInvoice)
}

func (activities *DocumentIngestionActivities) Embed(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	return activities.invoke(ctx, input, activities.service.Embed)
}

func (activities *DocumentIngestionActivities) Finalize(ctx context.Context, input documentworkflows.DocumentIngestionRequest) error {
	return activities.invoke(ctx, input, activities.service.Finalize)
}

func (activities *DocumentIngestionActivities) Fail(ctx context.Context, input documentworkflows.DocumentIngestionFailure) error {
	return activities.invoke(ctx, input.Job, func(ctx context.Context, job document.DocumentJob) error {
		return activities.service.Fail(ctx, job, documentworkflows.DocumentIngestionFailureCode(input.Code))
	})
}

func (activities *DocumentIngestionActivities) invoke(ctx context.Context, input documentworkflows.DocumentIngestionRequest, call func(context.Context, document.DocumentJob) error) error {
	if !validIngestionRequest(input) {
		return temporal.NewNonRetryableApplicationError("invalid ingestion identifiers", "invalid_job", nil)
	}
	activities.mu.Lock()
	if activities.closing {
		activities.mu.Unlock()
		return context.Canceled
	}
	activities.active.Add(1)
	activities.mu.Unlock()
	defer activities.active.Done()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stop := context.AfterFunc(activities.lifetime, cancel)
	defer stop()
	if activity.IsActivity(ctx) {
		done := make(chan struct{})
		go func() {
			defer close(done)
			ticker := time.NewTicker(3 * time.Second)
			defer ticker.Stop()
			activity.RecordHeartbeat(ctx)
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					activity.RecordHeartbeat(ctx)
				}
			}
		}()
		defer func() { cancel(); <-done }()
	}
	err := call(ctx, document.DocumentJob{AIAttempt: input.AIAttempt, AccountID: input.AccountID, DocumentID: input.DocumentID, Generation: input.Generation})
	if err == nil {
		return nil
	}
	if activities.lifetime.Err() != nil {
		return temporal.NewApplicationError("document worker is stopping", "processing_failed")
	}
	if errors.Is(err, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
		return temporal.NewCanceledError()
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return temporal.NewApplicationError("document processing deadline exceeded", "processing_timeout")
	}
	if errors.Is(err, document.ErrStaleJob) {
		return temporal.NewNonRetryableApplicationError("ingestion generation is no longer active", "stale_generation", nil)
	}
	if errors.Is(err, document.ErrOverloaded) {
		return temporal.NewApplicationErrorWithOptions("document processor is busy", "inference_unavailable", temporal.ApplicationErrorOptions{NextRetryDelay: 65 * time.Second})
	}
	var failure document.DocumentProcessingError
	if errors.As(err, &failure) {
		if !failure.Retryable {
			return temporal.NewNonRetryableApplicationError("document processing failed", documentworkflows.DocumentIngestionFailureCode(failure.Code), nil)
		}
		return temporal.NewApplicationError("document processing unavailable", documentworkflows.DocumentIngestionFailureCode(failure.Code))
	}
	return temporal.NewApplicationError("document processing unavailable", "processing_failed")
}

func validIngestionRequest(input documentworkflows.DocumentIngestionRequest) bool {
	account, accountErr := uuid.Parse(input.AccountID)
	id, idErr := uuid.Parse(input.DocumentID)
	return accountErr == nil && account != uuid.Nil && account.String() == input.AccountID && idErr == nil && id != uuid.Nil && id.String() == input.DocumentID && input.Generation > 0
}
