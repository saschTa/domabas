package handlers

import (
	"context"
	"io"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentService interface {
	Create(context.Context, string, domain.DocumentCreateInput) (domain.Document, error)
	Get(context.Context, string, string) (domain.Document, error)
	List(context.Context, string, domain.DocumentPageRequest) (domain.DocumentPage, error)
}

type DocumentIngestionService interface {
	Unlock(context.Context, domain.DocumentActor, string, int64, string) (domain.DocumentProcessing, error)
	RetryAI(context.Context, domain.DocumentActor, string, domain.DocumentReindexRequest) (domain.DocumentAIProcessing, error)
	NamespaceConfiguration(context.Context, domain.DocumentActor) (domain.DocumentProcessingConfiguration, error)
	Jobs(context.Context, domain.DocumentActor, domain.DocumentProcessingPageInput) (domain.DocumentJobPage, error)
	JobHistory(context.Context, domain.DocumentActor, string) (domain.DocumentJobHistory, error)
	Batches(context.Context, domain.DocumentActor, bool, domain.DocumentProcessingPageInput) (domain.DocumentReindexBatchPage, error)
	Batch(context.Context, domain.DocumentActor, bool, string) (domain.DocumentReindexBatch, error)
	CreateBatch(context.Context, domain.DocumentActor, bool, domain.DocumentReindexRequest) (domain.DocumentReindexBatch, error)
	OCR(context.Context, domain.DocumentActor, string) (domain.DocumentOCR, error)
	CorrectOCR(context.Context, domain.DocumentActor, string, domain.DocumentOCRCorrection) (domain.DocumentOCR, error)
	Delete(context.Context, domain.DocumentActor, string) error
	ReserveUpload(context.Context, domain.DocumentActor) (domain.DocumentUploadReservation, error)
	StageUpload(context.Context, domain.DocumentActor, domain.DocumentUploadReservation, string, io.Reader) (domain.DocumentFileReference, error)
	AcceptUpload(context.Context, domain.DocumentActor, domain.DocumentUploadReservation, domain.DocumentMetadata) (domain.Document, error)
	AbandonUpload(context.Context, domain.DocumentActor, domain.DocumentUploadReservation) error
	Update(context.Context, domain.DocumentActor, string, domain.DocumentMetadataPatch) (domain.Document, error)
	OpenContent(context.Context, domain.DocumentActor, string) (domain.DocumentContent, error)
	Processing(context.Context, domain.DocumentActor, string) (domain.DocumentProcessing, error)
	Retry(context.Context, domain.DocumentActor, string) (domain.DocumentProcessing, error)
	Search(context.Context, domain.DocumentActor, domain.DocumentSearchInput) (domain.DocumentSearchResults, error)
	GetProcessingConfiguration(context.Context, domain.DocumentActor) (domain.DocumentProcessingConfiguration, error)
	ModelContext(context.Context, domain.DocumentActor, string) (domain.DocumentModelContext, error)
	SetProcessingConfiguration(context.Context, domain.DocumentActor, domain.DocumentProcessingConfiguration) (domain.DocumentProcessingConfiguration, error)
}
