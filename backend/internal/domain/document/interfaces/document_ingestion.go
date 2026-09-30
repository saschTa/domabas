package interfaces

import (
	"context"
	"io"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentContentStore interface {
	StoreUnlocked(context.Context, m.DocumentFileReference, []byte) (m.DocumentFileReference, error)
	Stage(context.Context, m.DocumentUploadReservation, string, io.Reader) (m.DocumentFileReference, error)
	Open(context.Context, m.DocumentFileReference) (io.ReadCloser, error)
	Remove(context.Context, m.DocumentFileReference) error
}
type DocumentProcessor interface {
	UnlockPDF(context.Context, io.Reader, string) ([]byte, error)
	Extract(context.Context, io.Reader, string, m.DocumentProcessingConfiguration) (m.DocumentExtraction, error)
	Embed(context.Context, m.DocumentEmbeddingSpace, string, []string) (m.DocumentEmbedding, error)
	Ready(context.Context) error
}
type DocumentIngestionRepository interface {
	DocumentReindexRepository
	DocumentAIMaintenanceRepository
	UnlockFacts(context.Context, m.DocumentActor, string) (m.DocumentUnlockFacts, error)
	CompleteUnlock(context.Context, m.DocumentActor, m.DocumentFileReference, m.DocumentFileReference, int64, m.DocumentRetryCommand) (m.DocumentProcessing, error)
	ExecutionFacts(context.Context, m.DocumentPendingJob) (m.DocumentExecutionFacts, error)
	ResolveExecution(context.Context, m.DocumentPendingJob, m.DocumentExecutionResolution) error
	DocumentProcessingRepository
	OCR(context.Context, m.DocumentActor, string) (m.DocumentOCR, error)
	CorrectionFacts(context.Context, m.DocumentActor, string) (m.DocumentCorrectionFacts, error)
	CorrectOCR(context.Context, m.DocumentActor, string, m.DocumentCorrectionCommand) (m.DocumentOCR, error)
	Delete(context.Context, m.DocumentActor, string) error
	ReapDeleted(context.Context, int) ([]m.DocumentCleanupLease, error)
	DeletedReaped(context.Context, m.DocumentCleanupLease, m.DocumentCleanupCompletion) error
	Reserve(context.Context, m.DocumentActor, m.DocumentUploadReservation) (m.DocumentUploadReservation, error)
	Reservation(context.Context, m.DocumentActor, string) (m.DocumentUploadReservation, error)
	RecordStaged(context.Context, m.DocumentActor, string, m.DocumentFileReference) error
	UploadAcceptanceFacts(context.Context, m.DocumentActor, string) (m.DocumentUploadAcceptanceFacts, error)
	Accept(context.Context, m.DocumentActor, string, m.DocumentUploadAcceptanceCommand) (m.Document, error)
	Abandon(context.Context, m.DocumentActor, string) (*m.DocumentFileReference, error)
	Reap(context.Context, m.DocumentUploadRetentionPolicy) ([]m.DocumentFileReference, error)
	Reaped(context.Context, m.DocumentFileReference, m.DocumentUploadRetentionPolicy) error
	Update(context.Context, m.DocumentActor, string, m.DocumentMetadataPatch) (m.Document, error)
	Reference(context.Context, m.DocumentActor, string) (m.DocumentFileReference, error)
	Processing(context.Context, m.DocumentActor, string) (m.DocumentProcessing, error)
	RetryFacts(context.Context, m.DocumentActor, string) (m.DocumentRetryFacts, error)
	Retry(context.Context, m.DocumentActor, string, m.DocumentRetryCommand) (m.DocumentProcessing, error)
	Search(context.Context, m.DocumentActor, m.DocumentSearchInput, []float64) (m.DocumentSearchResults, error)
	GetConfiguration(context.Context, m.DocumentActor) (m.DocumentProcessingConfiguration, error)
	SetConfiguration(context.Context, m.DocumentActor, m.DocumentConfigurationChange) (m.DocumentProcessingConfiguration, error)
	ConfigurationCredential(context.Context, string) (string, error)
	Work(context.Context, m.DocumentJob, string) (m.DocumentProcessingWork, error)
	BeginWork(context.Context, m.DocumentProcessingCommand) error
	SaveExtractionEvidence(context.Context, m.DocumentExtractionCommand) error
	SaveEmbeddings(context.Context, m.DocumentEmbeddingCommand) error
	Publish(context.Context, m.DocumentPublicationCommand) error
	Fail(context.Context, m.DocumentJob, string) error
	DeliverySettings(context.Context) (m.DocumentDeliverySettings, error)
	Claim(context.Context, int, time.Duration, []m.DocumentReindexScheduleCommand, m.DocumentDeliveryPolicy, ...string) ([]m.DocumentOutboxLease, error)
	Acknowledge(context.Context, m.DocumentOutboxLease, string, string) error
	Release(context.Context, m.DocumentOutboxLease, time.Time) error
	Pending(context.Context, int) ([]m.DocumentPendingJob, error)
	FailExpired(context.Context, m.DocumentJob, string) error
}
