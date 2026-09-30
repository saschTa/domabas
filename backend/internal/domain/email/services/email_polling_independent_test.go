package services

import (
	"context"
	"testing"
	"time"

	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/email/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type independentInspectionRepository struct {
	p.EmailPollingRepository
	messageState                          string
	inspectionWritten, inspectionComplete bool
}

func (*independentInspectionRepository) Part(context.Context, m.EmailAttempt, m.EmailItem, string, string, string) (m.EmailPart, error) {
	return m.EmailPart{ID: "original-part", DocumentID: "accepted-original"}, nil
}
func (*independentInspectionRepository) SetStage(context.Context, m.EmailAttempt, string) error {
	return nil
}
func (r *independentInspectionRepository) MessageOutcome(_ context.Context, _ m.EmailAttempt, _ m.EmailItem, command m.EmailMessageOutcomeCommand) error {
	r.messageState = command.State
	return nil
}
func (r *independentInspectionRepository) InspectionOutcome(_ context.Context, _ m.EmailAttempt, _ m.EmailItem, command m.EmailInspectionCommand) error {
	r.inspectionWritten, r.inspectionComplete = true, command.State == "complete"
	return nil
}

type independentFailingInspector struct {
	p.EmailDocumentImporter
	err error
}

func (i independentFailingInspector) Inspect(context.Context, d.DocumentImportAuthority, func(d.DocumentEmailPart) error) (d.DocumentEmailInspection, error) {
	return d.DocumentEmailInspection{}, i.err
}

func TestIndependentTransientInspectionFailureKeepsAcceptedMailResumable(t *testing.T) {
	repository := &independentInspectionRepository{}
	service := NewEmailPollingService(repository, nil, nil, independentFailingInspector{err: d.DocumentProcessingError{Code: "storage_unavailable", Retryable: true}}, time.Now, emailTestAuthority{})
	item := m.EmailItem{ID: "source-message", ParentDocumentID: "accepted-original"}
	err := service.message(context.Background(), m.EmailWork{}, item, nil, time.Now())
	if err != nil || repository.messageState != "pending" || repository.inspectionWritten {
		t.Fatalf("transient original-read failure became permanent inspection outcome: message=%q inspectionWritten=%v complete=%v err=%v", repository.messageState, repository.inspectionWritten, repository.inspectionComplete, err)
	}
}

func TestIndependentDeletedOriginalRetiresOnlyItsPendingImport(t *testing.T) {
	repository := &independentInspectionRepository{}
	service := NewEmailPollingService(repository, nil, nil, independentFailingInspector{err: d.ErrNotFound}, time.Now, emailTestAuthority{})
	item := m.EmailItem{ID: "source-message", ParentDocumentID: "accepted-original"}
	err := service.message(context.Background(), m.EmailWork{}, item, nil, time.Now())
	if err != nil || repository.messageState != "deleted" || repository.inspectionWritten {
		t.Fatalf("deleted original was not a terminal source tombstone: %+v %v", repository, err)
	}
}

func (*independentInspectionRepository) MessageFacts(context.Context, m.EmailAttempt, m.EmailItem) (m.EmailMessageFacts, error) {
	return m.EmailMessageFacts{}, nil
}
