package temporal

import (
	"context"
	"errors"
	"sync"
	"time"

	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"
	"github.com/google/uuid"
	"go.temporal.io/sdk/temporal"
)

type DocumentReader interface {
	Get(context.Context, string, string) (document.Document, error)
}

type DocumentMetadataActivities struct {
	reader   DocumentReader
	mu       sync.Mutex
	closing  bool
	active   sync.WaitGroup
	lifetime context.Context
	cancel   context.CancelFunc
}

func NewDocumentMetadataActivities(reader DocumentReader) *DocumentMetadataActivities {
	ctx, cancel := context.WithCancel(context.Background())
	return &DocumentMetadataActivities{reader: reader, lifetime: ctx, cancel: cancel}
}

func (activities *DocumentMetadataActivities) Close() {
	// Worker.Stop can return before active database reads release their connections.
	activities.mu.Lock()
	activities.closing = true
	activities.cancel()
	activities.mu.Unlock()
	activities.active.Wait()
}

func (activities *DocumentMetadataActivities) ReadDocumentMetadata(ctx context.Context, input documentworkflows.DocumentMetadataRequest) (documentworkflows.DocumentMetadataResult, error) {
	if account, err := uuid.Parse(input.AccountID); err != nil || account == uuid.Nil {
		return documentworkflows.DocumentMetadataResult{}, temporal.NewNonRetryableApplicationError("invalid account identifier", "InvalidAccountID", nil)
	}
	if _, err := uuid.Parse(input.DocumentID); err != nil {
		return documentworkflows.DocumentMetadataResult{}, temporal.NewNonRetryableApplicationError("invalid document identifier", "InvalidDocumentID", nil)
	}
	activities.mu.Lock()
	if activities.closing {
		activities.mu.Unlock()
		return documentworkflows.DocumentMetadataResult{}, context.Canceled
	}
	activities.active.Add(1)
	activities.mu.Unlock()
	defer activities.active.Done()
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	stop := context.AfterFunc(activities.lifetime, cancel)
	defer stop()
	doc, err := activities.reader.Get(ctx, input.AccountID, input.DocumentID)
	if errors.Is(err, document.ErrNotFound) {
		return documentworkflows.DocumentMetadataResult{}, temporal.NewNonRetryableApplicationError("document not found", "DocumentNotFound", nil)
	}
	var validation document.DocumentValidationError
	if errors.As(err, &validation) {
		return documentworkflows.DocumentMetadataResult{}, temporal.NewNonRetryableApplicationError("invalid document identifier", "InvalidDocumentID", nil)
	}
	if err != nil {
		return documentworkflows.DocumentMetadataResult{}, temporal.NewApplicationError("document read failed", "DocumentReadFailed")
	}
	return documentworkflows.DocumentMetadataResult{ID: doc.ID, CreatedAt: doc.CreatedAt}, nil
}

func LegacyReadDocumentMetadata(context.Context, string) (documentworkflows.DocumentMetadataResult, error) {
	return documentworkflows.DocumentMetadataResult{}, temporal.NewNonRetryableApplicationError("legacy document work requires account scope", "AccountScopeRequired", nil)
}
