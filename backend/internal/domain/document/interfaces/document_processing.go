package interfaces

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentProcessingRepository interface {
	AIRetryFacts(context.Context, m.DocumentActor, string, string) (m.DocumentAIRetryFacts, error)
	RetryAI(context.Context, m.DocumentActor, string, m.DocumentAIRetryCommand) (m.DocumentAIProcessing, error)
	NamespaceConfiguration(context.Context, m.DocumentActor) (m.DocumentProcessingConfiguration, error)
	SearchConfiguration(context.Context, m.DocumentActor) (m.DocumentProcessingConfiguration, error)
	Jobs(context.Context, m.DocumentActor, m.DocumentProcessingPageInput, ...m.DocumentJobProjection) (m.DocumentJobPage, error)
	JobHistory(context.Context, m.DocumentActor, string, ...m.DocumentJobProjection) (m.DocumentJobHistory, error)
	Batches(context.Context, m.DocumentActor, bool, m.DocumentProcessingPageInput) (m.DocumentReindexBatchPage, error)
	Batch(context.Context, m.DocumentActor, bool, string) (m.DocumentReindexBatch, error)
	ReindexStartFacts(context.Context, m.DocumentActor, bool, string) (m.DocumentReindexStartFacts, error)
	CreateBatch(context.Context, m.DocumentActor, bool, m.DocumentReindexStartCommand) (m.DocumentReindexBatch, error)
}
