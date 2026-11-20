package document

import (
	"context"
	"fmt"
	documentmodels "github.com/domabas/domabas/backend/internal/domain/document/models"
	"log/slog"
	"path/filepath"
	"sync"
	"time"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/llm"
	records "github.com/domabas/domabas/backend/internal/data/document/models"

	documentsources "github.com/domabas/domabas/backend/internal/data/document/datasources"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/filesystem"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/mimecontent"
	"github.com/domabas/domabas/backend/internal/data/document/datasources/processor"

	documentrepos "github.com/domabas/domabas/backend/internal/data/document/repos"
	"github.com/domabas/domabas/backend/internal/data/postgres"

	documentinterfaces "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	documentservices "github.com/domabas/domabas/backend/internal/domain/document/services"
)

type DocumentOptions struct {
	Logger                                                                                         *slog.Logger
	Scheduler                                                                                      documentsources.DocumentResourceScheduler
	IngestionConcurrency                                                                           int
	AIConcurrency, EmbeddingQueueSize                                                              int
	IngestionConcurrencyMode, AIConcurrencyMode                                                    string
	IngestionRoot, StorageRoot, ProcessorURL, DashboardURL, LLMCredentialKey, LLMCredentialKeyFile string
}
type DocumentContainer struct {
	thumbnails *documentservices.DocumentThumbnailService
	ai         *documentservices.DocumentAIService
	llm        *llm.DocumentPropertyRemoteDataSource
	source     *documentsources.DocumentDataSource
	service    *documentservices.DocumentService
	ingestion  *documentservices.DocumentIngestionService
	imports    *documentservices.DocumentImportService
	vocabulary *documentservices.DocumentVocabularyService
	properties *documentservices.DocumentPropertyService
	files      *filesystem.DocumentFileSystemDataSource
	processor  *processor.RemoteDocumentProcessorDataSource
	closeOnce  sync.Once
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
	languageModel := llm.NewDocumentPropertyRemoteDataSource(options.Logger)
	capacity := options.IngestionConcurrency
	if capacity == 0 {
		capacity = 1
	}
	source := documentsources.NewDocumentLLMDataSource(database, files, options.DashboardURL, vault, options.Scheduler, records.DocumentIngestionLimits{Concurrency: capacity, AIConcurrency: max(1, options.AIConcurrency), EmbeddingQueueSize: max(1, options.EmbeddingQueueSize), ConcurrencyMode: options.IngestionConcurrencyMode, AIConcurrencyMode: options.AIConcurrencyMode, UnlimitedInference: true})
	if err := documentservices.NewDocumentInitializationService(documentrepos.NewDocumentInitializationRepository(source)).Initialize(ctx); err != nil {
		languageModel.Close()
		remote.Close()
		_ = files.Close()
		return nil, fmt.Errorf("initialize document pipeline: %w", err)
	}
	service := documentservices.NewDocumentService(documentrepos.NewDocumentRepository(source), now)
	ingestion := documentservices.NewDocumentIngestionService(documentrepos.NewDocumentIngestionRepository(source), documentrepos.NewDocumentContentRepository(files), documentrepos.NewDocumentProcessorRepository(remote), authority, now)
	imports := documentservices.NewDocumentImportService(documentrepos.NewDocumentImportRepository(source), documentrepos.NewDocumentContentRepository(files), documentrepos.NewDocumentEmailInspectionRepository(mimecontent.NewDocumentMimeContentDataSource()), authority, now)
	vocabulary := documentservices.NewDocumentVocabularyService(documentrepos.NewDocumentVocabularyRepository(source), authority)
	properties := documentservices.NewDocumentPropertyService(documentrepos.NewDocumentPropertyRepository(source), documentrepos.NewDocumentPropertyExtractionRepository(languageModel))
	thumbnails := documentservices.NewDocumentThumbnailService(documentrepos.NewDocumentThumbnailRepository(source), documentrepos.NewDocumentContentRepository(files), documentrepos.NewDocumentThumbnailProcessorRepository(remote), authority)
	container := &DocumentContainer{thumbnails: thumbnails, ai: documentservices.NewDocumentAIService(documentrepos.NewDocumentAIRepository(source)), llm: languageModel, source: source, service: service, ingestion: ingestion, imports: imports, vocabulary: vocabulary, properties: properties, files: files, processor: remote}
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
func (c *DocumentContainer) Close() {
	c.closeOnce.Do(func() { c.processor.Close(); c.llm.Close(); _ = c.files.Close() })
}
func (c *DocumentContainer) AI() *documentservices.DocumentAIService { return c.ai }
func (c *DocumentContainer) Properties() *documentservices.DocumentPropertyService {
	return c.properties
}
func (c *DocumentContainer) Thumbnails() *documentservices.DocumentThumbnailService {
	return c.thumbnails
}

func (c *DocumentContainer) IngestionThumbnail(ctx context.Context, job documentmodels.DocumentJob) error {
	j, err := c.source.IngestionThumbnailJob(ctx, job)
	if err != nil || j.ID == "" {
		return err
	}
	if err = c.thumbnails.Render(ctx, j); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err = c.thumbnails.Finish(ctx, j, documentmodels.DocumentThumbnailFailure(err)); err != nil {
			return err
		}
	}
	return c.source.CloseIngestionThumbnail(ctx, j)
}
