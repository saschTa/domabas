package repos

import (
	"context"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentIngestionSource interface {
	DocumentReindexSource
	DocumentAIMaintenanceSource
	UnlockFacts(context.Context, m.DocumentActor, string) (m.DocumentUnlockFacts, error)
	CompleteUnlockRecord(context.Context, m.DocumentActor, m.DocumentFileReference, m.DocumentFileReference, int64, m.DocumentRetryCommand) (r.DocumentProcessingRecord, error)
	ExecutionFacts(context.Context, m.DocumentPendingJob) (m.DocumentExecutionFacts, error)
	ResolveExecution(context.Context, m.DocumentPendingJob, m.DocumentExecutionResolution) error
	DocumentProcessingSource
	OCRRecord(context.Context, m.DocumentActor, string) (r.DocumentOCRRecord, error)
	CorrectionFacts(context.Context, m.DocumentActor, string) (m.DocumentCorrectionFacts, error)
	CorrectOCRRecord(context.Context, m.DocumentActor, string, m.DocumentCorrectionCommand) (r.DocumentOCRRecord, error)
	Delete(context.Context, m.DocumentActor, string) error
	ReapDeletedRecords(context.Context, int) ([]r.DocumentCleanupRecord, error)
	DeletedReaped(context.Context, m.DocumentCleanupLease, m.DocumentCleanupCompletion) error
	ReserveRecord(ctx context.Context, a m.DocumentActor, input m.DocumentUploadReservation) (r.DocumentReservationRecord, error)
	ReservationRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentReservationRecord, error)
	RecordStaged(ctx context.Context, a m.DocumentActor, id string, ref m.DocumentFileReference) error
	UploadAcceptanceFacts(context.Context, m.DocumentActor, string) (m.DocumentUploadAcceptanceFacts, error)
	AcceptRecord(ctx context.Context, a m.DocumentActor, id string, command m.DocumentUploadAcceptanceCommand) (r.DocumentRecord, error)
	AbandonRecord(ctx context.Context, a m.DocumentActor, id string) (*r.DocumentReferenceRecord, error)
	ReapRecords(ctx context.Context, policy m.DocumentUploadRetentionPolicy) ([]r.DocumentReferenceRecord, error)
	Reaped(ctx context.Context, ref m.DocumentFileReference, policy m.DocumentUploadRetentionPolicy) error
	UpdateRecord(ctx context.Context, a m.DocumentActor, id string, patch m.DocumentMetadataPatch) (r.DocumentRecord, error)
	ReferenceRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentReferenceRecord, error)
	ProcessingRecord(ctx context.Context, a m.DocumentActor, id string) (r.DocumentProcessingRecord, error)
	RetryFacts(context.Context, m.DocumentActor, string) (m.DocumentRetryFacts, error)
	RetryRecord(ctx context.Context, a m.DocumentActor, id string, command m.DocumentRetryCommand) (r.DocumentProcessingRecord, error)
	SearchRecord(ctx context.Context, a m.DocumentActor, input m.DocumentSearchInput, vector []float64) (r.DocumentSearchRecord, error)
	GetConfigurationRecord(ctx context.Context, a m.DocumentActor) (r.DocumentConfigurationRecord, error)
	SetConfigurationRecord(ctx context.Context, a m.DocumentActor, c m.DocumentConfigurationChange) (r.DocumentConfigurationRecord, error)
	PropertyCredential(context.Context, string) (string, error)
	WorkRecord(ctx context.Context, j m.DocumentJob, stage string) (r.DocumentWorkRecord, error)
	BeginWork(context.Context, m.DocumentProcessingCommand) error
	SaveExtractionEvidence(context.Context, m.DocumentExtractionCommand) error
	SaveEmbeddings(context.Context, m.DocumentEmbeddingCommand) error
	Publish(context.Context, m.DocumentPublicationCommand) error
	Fail(ctx context.Context, j m.DocumentJob, code string) error
	DeliverySettings(context.Context) (m.DocumentDeliverySettings, error)
	ClaimRecords(ctx context.Context, limit int, lease time.Duration, commands []m.DocumentReindexScheduleCommand, policy m.DocumentDeliveryPolicy, queue ...string) ([]r.DocumentLeaseRecord, error)
	Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error
	Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error
	PendingRecords(ctx context.Context, limit int) ([]r.DocumentPendingRecord, error)
	FailExpired(ctx context.Context, j m.DocumentJob, code string) error
}
type DocumentIngestionRepository struct{ source DocumentIngestionSource }

var _ p.DocumentIngestionRepository = (*DocumentIngestionRepository)(nil)

func NewDocumentIngestionRepository(source DocumentIngestionSource) *DocumentIngestionRepository {
	return &DocumentIngestionRepository{source}
}
func (rp *DocumentIngestionRepository) Reserve(ctx context.Context, a m.DocumentActor, input m.DocumentUploadReservation) (m.DocumentUploadReservation, error) {
	record, err := rp.source.ReserveRecord(ctx, a, input)
	return m.DocumentUploadReservation(record), err
}
func (rp *DocumentIngestionRepository) Reservation(ctx context.Context, a m.DocumentActor, id string) (m.DocumentUploadReservation, error) {
	record, err := rp.source.ReservationRecord(ctx, a, id)
	return m.DocumentUploadReservation(record), err
}
func (rp *DocumentIngestionRepository) RecordStaged(ctx context.Context, a m.DocumentActor, id string, ref m.DocumentFileReference) error {
	return rp.source.RecordStaged(ctx, a, id, ref)
}
func (rp *DocumentIngestionRepository) UploadAcceptanceFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentUploadAcceptanceFacts, error) {
	return rp.source.UploadAcceptanceFacts(ctx, a, id)
}
func (rp *DocumentIngestionRepository) Accept(ctx context.Context, a m.DocumentActor, id string, command m.DocumentUploadAcceptanceCommand) (m.Document, error) {
	record, err := rp.source.AcceptRecord(ctx, a, id, command)
	return documentIngestionRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) Abandon(ctx context.Context, a m.DocumentActor, id string) (*m.DocumentFileReference, error) {
	record, err := rp.source.AbandonRecord(ctx, a, id)
	if record == nil {
		return nil, err
	}
	result := documentReferenceRecordToDomainMapper(*record)
	return &result, err
}
func (rp *DocumentIngestionRepository) Reap(ctx context.Context, policy m.DocumentUploadRetentionPolicy) ([]m.DocumentFileReference, error) {
	records, err := rp.source.ReapRecords(ctx, policy)
	result := make([]m.DocumentFileReference, 0, len(records))
	for _, record := range records {
		result = append(result, documentReferenceRecordToDomainMapper(record))
	}
	return result, err
}
func (rp *DocumentIngestionRepository) Reaped(ctx context.Context, ref m.DocumentFileReference, policy m.DocumentUploadRetentionPolicy) error {
	return rp.source.Reaped(ctx, ref, policy)
}
func (rp *DocumentIngestionRepository) Update(ctx context.Context, a m.DocumentActor, id string, patch m.DocumentMetadataPatch) (m.Document, error) {
	record, err := rp.source.UpdateRecord(ctx, a, id, patch)
	return documentIngestionRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) Reference(ctx context.Context, a m.DocumentActor, id string) (m.DocumentFileReference, error) {
	record, err := rp.source.ReferenceRecord(ctx, a, id)
	return documentReferenceRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) Processing(ctx context.Context, a m.DocumentActor, id string) (m.DocumentProcessing, error) {
	record, err := rp.source.ProcessingRecord(ctx, a, id)
	return documentProcessingRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) RetryFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentRetryFacts, error) {
	return rp.source.RetryFacts(ctx, a, id)
}
func (rp *DocumentIngestionRepository) Retry(ctx context.Context, a m.DocumentActor, id string, command m.DocumentRetryCommand) (m.DocumentProcessing, error) {
	record, err := rp.source.RetryRecord(ctx, a, id, command)
	return documentProcessingRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) Search(ctx context.Context, a m.DocumentActor, input m.DocumentSearchInput, vector []float64) (m.DocumentSearchResults, error) {
	record, err := rp.source.SearchRecord(ctx, a, input, vector)
	return documentSearchRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) GetConfiguration(ctx context.Context, a m.DocumentActor) (m.DocumentProcessingConfiguration, error) {
	record, err := rp.source.GetConfigurationRecord(ctx, a)
	return documentConfigurationRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) SetConfiguration(ctx context.Context, a m.DocumentActor, c m.DocumentConfigurationChange) (m.DocumentProcessingConfiguration, error) {
	record, err := rp.source.SetConfigurationRecord(ctx, a, c)
	return documentConfigurationRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) ConfigurationCredential(ctx context.Context, id string) (string, error) {
	return rp.source.PropertyCredential(ctx, id)
}
func (rp *DocumentIngestionRepository) Work(ctx context.Context, j m.DocumentJob, stage string) (m.DocumentProcessingWork, error) {
	record, err := rp.source.WorkRecord(ctx, j, stage)
	return documentWorkRecordToDomainMapper(record), err
}
func (rp *DocumentIngestionRepository) BeginWork(ctx context.Context, command m.DocumentProcessingCommand) error {
	return rp.source.BeginWork(ctx, command)
}
func (rp *DocumentIngestionRepository) SaveEmbeddings(ctx context.Context, command m.DocumentEmbeddingCommand) error {
	return rp.source.SaveEmbeddings(ctx, command)
}
func (rp *DocumentIngestionRepository) Publish(ctx context.Context, command m.DocumentPublicationCommand) error {
	return rp.source.Publish(ctx, command)
}
func (rp *DocumentIngestionRepository) Fail(ctx context.Context, j m.DocumentJob, code string) error {
	return rp.source.Fail(ctx, j, code)
}
func (rp *DocumentIngestionRepository) DeliverySettings(ctx context.Context) (m.DocumentDeliverySettings, error) {
	return rp.source.DeliverySettings(ctx)
}
func (rp *DocumentIngestionRepository) Claim(ctx context.Context, limit int, lease time.Duration, commands []m.DocumentReindexScheduleCommand, policy m.DocumentDeliveryPolicy, queue ...string) ([]m.DocumentOutboxLease, error) {
	records, err := rp.source.ClaimRecords(ctx, limit, lease, commands, policy, queue...)
	result := make([]m.DocumentOutboxLease, 0, len(records))
	for _, record := range records {
		result = append(result, documentLeaseRecordToDomainMapper(record))
	}
	return result, err
}
func (rp *DocumentIngestionRepository) Acknowledge(ctx context.Context, l m.DocumentOutboxLease, workflow, run string) error {
	return rp.source.Acknowledge(ctx, l, workflow, run)
}
func (rp *DocumentIngestionRepository) Release(ctx context.Context, l m.DocumentOutboxLease, next time.Time) error {
	return rp.source.Release(ctx, l, next)
}
func (rp *DocumentIngestionRepository) Pending(ctx context.Context, limit int) ([]m.DocumentPendingJob, error) {
	records, err := rp.source.PendingRecords(ctx, limit)
	result := make([]m.DocumentPendingJob, 0, len(records))
	for _, record := range records {
		result = append(result, documentPendingRecordToDomainMapper(record))
	}
	return result, err
}
func (rp *DocumentIngestionRepository) FailExpired(ctx context.Context, j m.DocumentJob, code string) error {
	return rp.source.FailExpired(ctx, j, code)
}

func (rp *DocumentIngestionRepository) ExecutionFacts(ctx context.Context, pending m.DocumentPendingJob) (m.DocumentExecutionFacts, error) {
	return rp.source.ExecutionFacts(ctx, pending)
}
func (rp *DocumentIngestionRepository) ResolveExecution(ctx context.Context, pending m.DocumentPendingJob, command m.DocumentExecutionResolution) error {
	return rp.source.ResolveExecution(ctx, pending, command)
}

func (rp *DocumentIngestionRepository) SaveExtractionEvidence(ctx context.Context, command m.DocumentExtractionCommand) error {
	return rp.source.SaveExtractionEvidence(ctx, command)
}

func (rp *DocumentIngestionRepository) UnlockFacts(ctx context.Context, a m.DocumentActor, id string) (m.DocumentUnlockFacts, error) {
	return rp.source.UnlockFacts(ctx, a, id)
}
func (rp *DocumentIngestionRepository) CompleteUnlock(ctx context.Context, a m.DocumentActor, original, unlocked m.DocumentFileReference, generation int64, command m.DocumentRetryCommand) (m.DocumentProcessing, error) {
	value, err := rp.source.CompleteUnlockRecord(ctx, a, original, unlocked, generation, command)
	return documentProcessingRecordToDomainMapper(value), err
}
