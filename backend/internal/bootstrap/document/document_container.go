package document

import (
	"context"
	"fmt"
	"log/slog"
	"path/filepath"
	"sync"
	"time"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/llm"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	documentworkflows "github.com/domabas/domabas/backend/internal/domain/document/workflows"

	documentsources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/filesystem"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/mimecontent"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/processor"

	documentrepos "github.com/domabas/domabas/backend/internal/data/document/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"

	documentinterfaces "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	documentservices "github.com/domabas/domabas/backend/internal/domain/document/services"

	documenttemporal "github.com/domabas/domabas/backend/internal/data/document/temporal"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

type DocumentOptions struct {
	Logger                                                                                                       *slog.Logger
	Scheduler                                                                                                    documentsources.DocumentResourceScheduler
	IngestionConcurrency                                                                                         int
	AIConcurrency, OllamaQueueSize                                                                               int
	IngestionConcurrencyMode, AIConcurrencyMode                                                                  string
	IngestionRoot, StorageRoot, ProcessorURL, DashboardURL, LLMOllamaURL, LLMCredentialKey, LLMCredentialKeyFile string
}
type DocumentContainer struct {
	thumbnails          *documentservices.DocumentThumbnailService
	thumbnailActivities *documenttemporal.DocumentThumbnailActivities
	ai                  *documentservices.DocumentAIService
	aiActivities        *documenttemporal.DocumentAIActivities
	llm                 *llm.DocumentPropertyRemoteDataSource
	source              *documentsources.DocumentDataSource
	service             *documentservices.DocumentService
	ingestion           *documentservices.DocumentIngestionService
	imports             *documentservices.DocumentImportService
	vocabulary          *documentservices.DocumentVocabularyService
	activities          *documenttemporal.DocumentMetadataActivities
	properties          *documentservices.DocumentPropertyService
	ingestionActivities *documenttemporal.DocumentIngestionActivities
	files               *filesystem.DocumentFileSystemDataSource
	processor           *processor.RemoteDocumentProcessorDataSource
	closeOnce           sync.Once
}

func NewDocumentContainer(ctx context.Context, database *postgres.PostgresDatabase, authority documentinterfaces.DocumentAuthority, options DocumentOptions, now func() time.Time) (*DocumentContainer, error) {
	files, err := filesystem.NewDocumentFileSystemDataSource(options.IngestionRoot, options.StorageRoot)
	if err != nil {
		return nil, fmt.Errorf("open document storage: %w", err)
	}
	remote, err := processor.NewRemoteDocumentProcessorDataSource(options.ProcessorURL)
	if err != nil {
		_ = files.Close()
		return nil, err
	}
	if options.LLMCredentialKeyFile == "" {
		options.LLMCredentialKeyFile = filepath.Join(options.StorageRoot, ".secrets", "llm.key")
	}
	key, err := documentsources.CredentialKey(ctx, database, options.LLMCredentialKey, options.LLMCredentialKeyFile)
	if err != nil {
		remote.Close()
		_ = files.Close()
		return nil, err
	}
	vault, err := documentsources.CredentialVault(key)
	if err != nil {
		remote.Close()
		_ = files.Close()
		return nil, err
	}
	if options.LLMOllamaURL == "" {
		options.LLMOllamaURL = "http://127.0.0.1:11435"
	}
	languageModel, err := llm.NewDocumentPropertyRemoteDataSource(options.LLMOllamaURL, options.Logger)
	if err != nil {
		remote.Close()
		_ = files.Close()
		return nil, err
	}
	capacity := options.IngestionConcurrency
	if capacity == 0 {
		capacity = 1
	}
	source := documentsources.NewDocumentLLMDataSource(database, files, options.DashboardURL, vault, options.Scheduler, records.DocumentIngestionLimits{Concurrency: capacity, AIConcurrency: max(1, options.AIConcurrency), OllamaQueueSize: max(1, options.OllamaQueueSize), ConcurrencyMode: options.IngestionConcurrencyMode, AIConcurrencyMode: options.AIConcurrencyMode, UnlimitedInference: true})
	if err := documentservices.NewDocumentInitializationService(documentrepos.NewDocumentInitializationRepository(source)).Initialize(ctx); err != nil {
		languageModel.Close()
		remote.Close()
		_ = files.Close()
		return nil, fmt.Errorf("initialize document pipeline: %w", err)
	}
	service := documentservices.NewDocumentService(documentrepos.NewDocumentRepository(source), now)
	ingestion := documentservices.NewDocumentIngestionService(documentrepos.NewDocumentIngestionRepository(source), documentrepos.NewDocumentContentRepository(files), documentrepos.NewDocumentProcessorRepository(remote), authority, now, documentrepos.NewDocumentModelContextRepository(languageModel))
	imports := documentservices.NewDocumentImportService(documentrepos.NewDocumentImportRepository(source), documentrepos.NewDocumentContentRepository(files), documentrepos.NewDocumentEmailInspectionRepository(mimecontent.NewDocumentMimeContentDataSource()), authority, now)
	vocabulary := documentservices.NewDocumentVocabularyService(documentrepos.NewDocumentVocabularyRepository(source), authority)
	properties := documentservices.NewDocumentPropertyService(documentrepos.NewDocumentPropertyRepository(source), documentrepos.NewDocumentPropertyExtractionRepository(languageModel))
	thumbnails := documentservices.NewDocumentThumbnailService(documentrepos.NewDocumentThumbnailRepository(source), documentrepos.NewDocumentContentRepository(files), documentrepos.NewDocumentThumbnailProcessorRepository(remote), authority)
	container := &DocumentContainer{thumbnails: thumbnails, ai: documentservices.NewDocumentAIService(documentrepos.NewDocumentAIRepository(source)), llm: languageModel, source: source, service: service, ingestion: ingestion, imports: imports, vocabulary: vocabulary, activities: documenttemporal.NewDocumentMetadataActivities(service), properties: properties, files: files, processor: remote}
	if err := files.Ready(ctx); err != nil {
		container.Close()
		return nil, fmt.Errorf("document storage readiness: %w", err)
	}
	for {
		if err := remote.Ready(ctx); err == nil {
			return container, nil
		}
		timer := time.NewTimer(time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			container.Close()
			return nil, fmt.Errorf("document processor startup: %w", ctx.Err())
		case <-timer.C:
		}
	}
}
func (container *DocumentContainer) LanguageModel() *llm.DocumentPropertyRemoteDataSource {
	return container.llm
}
func (container *DocumentContainer) Credentials() *documentsources.DocumentDataSource {
	return container.source
}
func (container *DocumentContainer) Service() *documentservices.DocumentService {
	return container.service
}
func (container *DocumentContainer) Ingestion() *documentservices.DocumentIngestionService {
	return container.ingestion
}
func (container *DocumentContainer) Importer() *documentservices.DocumentImportService {
	return container.imports
}
func (container *DocumentContainer) Vocabulary() *documentservices.DocumentVocabularyService {
	return container.vocabulary
}
func (container *DocumentContainer) Ping(ctx context.Context) error {
	if err := container.source.ProcessingReady(ctx); err != nil {
		return fmt.Errorf("pipeline compatibility: %w", err)
	}
	if err := container.files.Ready(ctx); err != nil {
		return fmt.Errorf("document storage readiness: %w", err)
	}
	if err := container.processor.Ready(ctx); err != nil {
		return fmt.Errorf("document processor readiness: %w", err)
	}
	return nil
}
func (container *DocumentContainer) RegisterWorker(registry worker.Registry, invoices documenttemporal.DocumentInvoiceService) {
	container.ingestionActivities = documenttemporal.NewDocumentIngestionActivities(container.ingestion, container.properties, invoices)
	registry.RegisterWorkflowWithOptions(documentworkflows.LegacyDocumentMetadataWorkflow, workflow.RegisterOptions{Name: documentworkflows.LegacyDocumentMetadataWorkflowName})
	registry.RegisterActivityWithOptions(documenttemporal.LegacyReadDocumentMetadata, activity.RegisterOptions{Name: documentworkflows.LegacyReadDocumentMetadataActivity})
	registry.RegisterWorkflowWithOptions(documentworkflows.DocumentMetadataWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentMetadataWorkflowName})
	registry.RegisterActivityWithOptions(container.activities.ReadDocumentMetadata, activity.RegisterOptions{Name: documentworkflows.ReadDocumentMetadataActivity})
	registry.RegisterWorkflowWithOptions(documentworkflows.DocumentSearchableWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentSearchableWorkflowName})
	registry.RegisterWorkflowWithOptions(documentworkflows.DocumentIngestionWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentIngestionWorkflowName})
	registry.RegisterActivityWithOptions(container.ingestionActivities.Extract, activity.RegisterOptions{Name: documentworkflows.ExtractDocumentActivity})
	registry.RegisterActivityWithOptions(container.ingestionActivities.Invoice, activity.RegisterOptions{Name: documentworkflows.InvoiceDocumentActivity})
	registry.RegisterActivityWithOptions(container.ingestionActivities.Enrich, activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
	registry.RegisterActivityWithOptions(container.ingestionActivities.Embed, activity.RegisterOptions{Name: documentworkflows.EmbedDocumentActivity})
	registry.RegisterActivityWithOptions(container.ingestionActivities.Finalize, activity.RegisterOptions{Name: documentworkflows.FinalizeDocumentActivity})
	registry.RegisterActivityWithOptions(container.ingestionActivities.Fail, activity.RegisterOptions{Name: documentworkflows.FailDocumentActivity})
}
func (container *DocumentContainer) Close() {
	container.closeOnce.Do(func() {
		container.DrainThumbnails()
		container.DrainAI()
		container.activities.Close()
		if container.ingestionActivities != nil {
			container.ingestionActivities.Close()
		}
		container.processor.Close()
		container.llm.Close()
		_ = container.files.Close()
	})
}

func (container *DocumentContainer) AI() *documentservices.DocumentAIService { return container.ai }
func (container *DocumentContainer) RegisterAIWorker(registry worker.Registry, invoices documenttemporal.DocumentInvoiceService) {
	container.aiActivities = documenttemporal.NewDocumentAIActivities(container.ai, container.properties, invoices)
	registry.RegisterWorkflowWithOptions(documentworkflows.DocumentAIWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentAIWorkflowName})
	registry.RegisterActivityWithOptions(container.aiActivities.Invoice, activity.RegisterOptions{Name: documentworkflows.InvoiceDocumentActivity})
	registry.RegisterActivityWithOptions(container.aiActivities.Enrich, activity.RegisterOptions{Name: documentworkflows.EnrichDocumentActivity})
	registry.RegisterActivityWithOptions(container.aiActivities.Complete, activity.RegisterOptions{Name: documentworkflows.CompleteDocumentAIActivity})
	registry.RegisterActivityWithOptions(container.aiActivities.Fail, activity.RegisterOptions{Name: documentworkflows.FailDocumentAIActivity})
}
func (container *DocumentContainer) DrainAI() {
	if container.aiActivities != nil {
		container.aiActivities.Close()
	}
}

func (c *DocumentContainer) Thumbnails() *documentservices.DocumentThumbnailService {
	return c.thumbnails
}
func (c *DocumentContainer) RegisterThumbnailWorker(registry worker.Registry) {
	c.thumbnailActivities = documenttemporal.NewDocumentThumbnailActivities(c.thumbnails)
	registry.RegisterWorkflowWithOptions(documentworkflows.DocumentThumbnailWorkflow, workflow.RegisterOptions{Name: documentworkflows.DocumentThumbnailWorkflowName})
	registry.RegisterActivityWithOptions(c.thumbnailActivities.Render, activity.RegisterOptions{Name: documentworkflows.RenderDocumentThumbnailActivity})
	registry.RegisterActivityWithOptions(c.thumbnailActivities.Finish, activity.RegisterOptions{Name: documentworkflows.FinishDocumentThumbnailActivity})
}
func (c *DocumentContainer) DrainThumbnails() {
	if c.thumbnailActivities != nil {
		c.thumbnailActivities.Close()
	}
}
