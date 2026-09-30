package bootstrap

import (
	"context"
	"fmt"
	chatcontainer "github.com/domabas/domabas/backend/internal/bootstrap/chat"
	schedulercontainer "github.com/domabas/domabas/backend/internal/bootstrap/scheduler"
	chattemporal "github.com/domabas/domabas/backend/internal/data/chat/temporal"
	chathandlers "github.com/domabas/domabas/backend/internal/presentation/chat/handlers"
	"log/slog"
	"net/http"
	"path/filepath"
	"sync"
	"time"

	documentcontainer "github.com/domabas/domabas/backend/internal/bootstrap/document"
	emailcontainer "github.com/domabas/domabas/backend/internal/bootstrap/email"
	identitycontainer "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	invoicecontainer "github.com/domabas/domabas/backend/internal/bootstrap/invoice"
	paperlesscontainer "github.com/domabas/domabas/backend/internal/bootstrap/paperless"
	realtimecontainer "github.com/domabas/domabas/backend/internal/bootstrap/realtime"
	"github.com/domabas/domabas/backend/internal/config"
	documenttemporal "github.com/domabas/domabas/backend/internal/data/document/temporal"
	emailtemporal "github.com/domabas/domabas/backend/internal/data/email/temporal"
	paperlesstemporal "github.com/domabas/domabas/backend/internal/data/paperless/temporal"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	temporaldata "github.com/domabas/domabas/backend/internal/data/temporal"
	documenthandlers "github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	emailhandlers "github.com/domabas/domabas/backend/internal/presentation/email/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	identityhandlers "github.com/domabas/domabas/backend/internal/presentation/identity/handlers"
	invoicehandlers "github.com/domabas/domabas/backend/internal/presentation/invoice/handlers"
	paperlesshandlers "github.com/domabas/domabas/backend/internal/presentation/paperless/handlers"
	"go.temporal.io/sdk/worker"
)

type BackendApp struct {
	thumbnailWorker     *temporalWorkerLifecycle
	thumbnailDispatcher *documenttemporal.DocumentThumbnailDispatcher
	chatWorker          *temporalWorkerLifecycle
	chatDispatcher      *chattemporal.ChatDispatcher
	aiWorker            *temporalWorkerLifecycle
	aiDispatcher        *documenttemporal.DocumentIngestionDispatcher
	paperlessWorker     *temporalWorkerLifecycle
	paperlessDispatcher *paperlesstemporal.PaperlessImportDispatcher
	Handler             http.Handler
	source              *postgres.PostgresDataSource
	temporal            *temporaldata.TemporalDataSource
	worker              *temporalWorkerLifecycle
	documents           *documentcontainer.DocumentContainer
	dispatcher          *documenttemporal.DocumentIngestionDispatcher
	emailWorker         *temporalWorkerLifecycle
	emailDispatcher     *emailtemporal.EmailPollDispatcher
	realtime            *realtimecontainer.RealtimeContainer
	fatal               chan error
	cancel              context.CancelFunc
	listeners           sync.WaitGroup
	closeOnce           sync.Once
}

func NewBackendApp(ctx context.Context, config config.BackendConfig, logger *slog.Logger) (*BackendApp, error) {
	dependencyContext, cancelDependencies := context.WithTimeout(ctx, 30*time.Second)
	defer cancelDependencies()
	source, err := postgres.NewPostgresDataSource(dependencyContext, config.DatabaseURL)
	if err != nil {
		return nil, err
	}
	if err := source.Migrate(ctx); err != nil {
		source.Close()
		return nil, err
	}
	cancelDependencies()
	dependencyContext, cancelDependencies = context.WithTimeout(ctx, 30*time.Second)
	defer cancelDependencies()
	temporalSource, err := temporaldata.NewTemporalDataSource(dependencyContext, config.TemporalAddress, config.TemporalNamespace, logger)
	if err != nil {
		source.Close()
		return nil, err
	}
	cancelDependencies()
	identities, err := identitycontainer.NewIdentityContainer(source.Database(), time.Now)
	if err != nil {
		temporalSource.Close()
		source.Close()
		return nil, err
	}
	scheduler, err := schedulercontainer.NewSchedulerContainer(ctx, source.Database(), identities.Service(), config.OllamaMaxQueue, config.LLMOllamaURL)
	if err != nil {
		temporalSource.Close()
		source.Close()
		return nil, fmt.Errorf("initialize workload scheduler: %w", err)
	}
	documents, err := documentcontainer.NewDocumentContainer(ctx, source.Database(), identities.Service(), documentcontainer.DocumentOptions{Logger: logger, Scheduler: scheduler.Admission(), IngestionConcurrency: config.DocumentIngestionConcurrency, AIConcurrency: config.DocumentAIConcurrency, OllamaQueueSize: config.OllamaMaxQueue, IngestionConcurrencyMode: config.DocumentIngestionConcurrencyMode, AIConcurrencyMode: config.DocumentAIConcurrencyMode, LLMOllamaURL: config.LLMOllamaURL, LLMCredentialKey: config.LLMCredentialKey, LLMCredentialKeyFile: config.LLMCredentialKeyFile, IngestionRoot: config.DocumentIngestionRoot, StorageRoot: config.DocumentStorageRoot, ProcessorURL: config.DocumentProcessorURL, DashboardURL: config.TemporalUIURL}, time.Now)
	if err != nil {
		temporalSource.Close()
		source.Close()
		return nil, err
	}
	invoices := invoicecontainer.NewInvoiceService(source.Database(), identities.Service(), documents.LanguageModel(), documents.Credentials(), logger)
	keyFile := config.PaperlessCredentialKeyFile
	if keyFile == "" {
		keyFile = filepath.Join(config.DocumentStorageRoot, ".secrets", "paperless.key")
	}
	imports, err := paperlesscontainer.NewPaperlessJobsService(ctx, source.Database(), identities.Service(), config.PaperlessCredentialKey, keyFile, config.TemporalTaskQueue+"-paperless", documents.Ingestion(), scheduler.Admission())
	if err != nil {
		documents.Close()
		temporalSource.Close()
		source.Close()
		return nil, err
	}
	dispatcher := documenttemporal.NewDocumentIngestionDispatcher(documents.Ingestion(), temporalSource.Client(), config.TemporalTaskQueue, logger, temporalSource.Ping)
	owner := newTemporalWorkerLifecycle(func() { dispatcher.Close(); documents.Close() })
	queueWorker := worker.New(temporalSource.Client(), config.TemporalTaskQueue, worker.Options{
		MaxConcurrentActivityExecutionSize: 256,
		WorkerStopTimeout:                  5 * time.Second,
		OnFatalError:                       owner.onFatalError,
	})
	documents.RegisterWorker(queueWorker, invoices)
	if err := owner.Start(queueWorker); err != nil {
		temporalSource.Close()
		source.Close()
		return nil, fmt.Errorf("start Temporal worker: %w", err)
	}
	if err := dispatcher.Start(); err != nil {
		owner.Close()
		temporalSource.Close()
		source.Close()
		return nil, fmt.Errorf("start document dispatcher: %w", err)
	}
	emailKeyFile := config.EmailCredentialKeyFile
	if emailKeyFile == "" {
		emailKeyFile = filepath.Join(config.DocumentStorageRoot, ".secrets", "email.key")
	}
	emails, err := emailcontainer.NewEmailContainer(ctx, source.Database(), identities.Service(), documents.Importer(), temporalSource.Client(), emailcontainer.EmailOptions{Scheduler: scheduler.Admission(), CredentialKeys: config.EmailCredentialKeys, ActiveKeyID: config.EmailActiveKeyID, CredentialKeyFile: emailKeyFile, CAFile: config.EmailIMAPCAFile, AllowedHosts: config.EmailIMAPAllowedHosts}, time.Now)
	if err != nil {
		dispatcher.Close()
		owner.Close()
		temporalSource.Close()
		source.Close()
		return nil, fmt.Errorf("initialize email ingestion: %w", err)
	}
	emailQueue := config.TemporalTaskQueue + "-email"
	emailDispatcher := emailtemporal.NewEmailPollDispatcher(emails.Polling(), emails.Rotation(), temporalSource.Client(), emailQueue, logger, temporalSource.Ping)
	emailOwner := newTemporalWorkerLifecycle(func() { emailDispatcher.Close(); emails.Close() })
	emailWorker := worker.New(temporalSource.Client(), emailQueue, worker.Options{MaxConcurrentActivityExecutionSize: 256, WorkerStopTimeout: 5 * time.Second, OnFatalError: emailOwner.onFatalError})
	emails.RegisterWorker(emailWorker)
	if err := emailOwner.Start(emailWorker); err != nil {
		dispatcher.Close()
		owner.Close()
		temporalSource.Close()
		source.Close()
		return nil, fmt.Errorf("start email Temporal worker: %w", err)
	}
	if err := emailDispatcher.Start(); err != nil {
		emailOwner.Close()
		dispatcher.Close()
		owner.Close()
		temporalSource.Close()
		source.Close()
		return nil, fmt.Errorf("start email dispatcher: %w", err)
	}
	lifetime, cancel := context.WithCancel(context.Background())
	app := &BackendApp{source: source, temporal: temporalSource, worker: owner, documents: documents, dispatcher: dispatcher, emailWorker: emailOwner, emailDispatcher: emailDispatcher, fatal: make(chan error, 1), cancel: cancel}
	thumbnailQueue := config.TemporalTaskQueue + "-thumbnail"
	app.thumbnailDispatcher = documenttemporal.NewDocumentThumbnailDispatcher(documents.Thumbnails(), temporalSource.Client(), thumbnailQueue, logger, temporalSource.Ping)
	app.thumbnailWorker = newTemporalWorkerLifecycle(documents.DrainThumbnails)
	thumbnailWorker := worker.New(temporalSource.Client(), thumbnailQueue, worker.Options{MaxConcurrentActivityExecutionSize: 256, WorkerStopTimeout: 5 * time.Second, OnFatalError: app.thumbnailWorker.onFatalError})
	documents.RegisterThumbnailWorker(thumbnailWorker)
	if err := app.thumbnailWorker.Start(thumbnailWorker); err != nil {
		app.Close()
		return nil, fmt.Errorf("start thumbnail worker: %w", err)
	}
	if err := app.thumbnailDispatcher.Start(); err != nil {
		app.Close()
		return nil, fmt.Errorf("start thumbnail dispatcher: %w", err)
	}
	aiQueue := config.TemporalTaskQueue + "-ai"
	app.aiDispatcher = documenttemporal.NewDocumentIngestionDispatcher(documents.AI(), temporalSource.Client(), aiQueue, logger, temporalSource.Ping)
	app.aiWorker = newTemporalWorkerLifecycle(documents.DrainAI)
	aiWorker := worker.New(temporalSource.Client(), aiQueue, worker.Options{MaxConcurrentActivityExecutionSize: 256, WorkerStopTimeout: 5 * time.Second, OnFatalError: app.aiWorker.onFatalError})
	documents.RegisterAIWorker(aiWorker, invoices)
	if err := app.aiWorker.Start(aiWorker); err != nil {
		app.Close()
		return nil, fmt.Errorf("start AI worker: %w", err)
	}
	if err := app.aiDispatcher.Start(); err != nil {
		app.Close()
		return nil, fmt.Errorf("start AI dispatcher: %w", err)
	}
	importActivities := paperlesstemporal.NewPaperlessImportActivities(imports)
	app.paperlessDispatcher = paperlesstemporal.NewPaperlessImportDispatcher(imports, temporalSource.Client())
	app.paperlessWorker = newTemporalWorkerLifecycle(importActivities.Close)
	importWorker := worker.New(temporalSource.Client(), config.TemporalTaskQueue+"-paperless", worker.Options{MaxConcurrentActivityExecutionSize: 256, WorkerStopTimeout: 5 * time.Second, OnFatalError: app.paperlessWorker.onFatalError})
	importActivities.Register(importWorker)
	if err := app.paperlessWorker.Start(importWorker); err != nil {
		app.Close()
		return nil, fmt.Errorf("start Paperless worker: %w", err)
	}
	if err := app.paperlessDispatcher.Start(ctx); err != nil {
		app.Close()
		return nil, fmt.Errorf("start Paperless dispatcher: %w", err)
	}
	chatQueue := config.TemporalTaskQueue + "-chat"
	chat, err := chatcontainer.NewChatContainer(ctx, source.Database(), identities.Service(), scheduler.Admission(), config.DocumentStorageRoot, config.LLMOllamaURL, chatQueue, logger)
	if err != nil {
		app.Close()
		return nil, fmt.Errorf("initialize chat: %w", err)
	}
	app.chatDispatcher = chattemporal.NewChatDispatcher(chat.Execution(), temporalSource.Client(), chatQueue, logger, temporalSource.Ping)
	app.chatWorker = newTemporalWorkerLifecycle(chat.Close)
	chatWorker := worker.New(temporalSource.Client(), chatQueue, worker.Options{MaxConcurrentActivityExecutionSize: 256, WorkerStopTimeout: 5 * time.Second, OnFatalError: app.chatWorker.onFatalError})
	chat.RegisterWorker(chatWorker)
	if err := app.chatWorker.Start(chatWorker); err != nil {
		app.Close()
		return nil, fmt.Errorf("start chat worker: %w", err)
	}
	if err := app.chatDispatcher.Start(ctx); err != nil {
		app.Close()
		return nil, fmt.Errorf("start chat dispatcher: %w", err)
	}
	app.realtime, err = realtimecontainer.NewRealtimeContainer(ctx, source.Database(), config.DatabaseURL, identities.Service(), identities.Authorizer(), config.CORSOrigins)
	if err != nil {
		app.Close()
		return nil, fmt.Errorf("initialize realtime: %w", err)
	}
	for _, worker := range []*temporalWorkerLifecycle{owner, emailOwner, app.paperlessWorker, app.aiWorker, app.chatWorker, app.thumbnailWorker} {
		app.listeners.Add(1)
		go func() {
			defer app.listeners.Done()
			select {
			case err := <-worker.fatal:
				select {
				case app.fatal <- err:
				case <-lifetime.Done():
				}
			case <-lifetime.Done():
			}
		}()
	}
	handler := httpapi.NewHTTPHandler(documenthandlers.NewDocumentHandler(documents.Service(), documents.Ingestion(), documents.Importer(), documents.Vocabulary(), logger).WithThumbnails(documents.Thumbnails()), identityhandlers.NewIdentityHandler(identities.Service(), identities.Activity(), logger), emailhandlers.NewEmailHandler(emails.Service(), logger), app, app.realtime.Handler(), invoicehandlers.NewInvoiceHandler(invoices, logger), paperlesshandlers.NewPaperlessHandler(imports)).WithChat(chathandlers.NewChatHandler(chat.Service())).WithScheduler(scheduler.Handler())
	app.Handler = httpapi.NewHTTPRouter(handler, transport.NewHTTPIdentityGuard(identities.Service(), identities.Authorizer()), config.CORSOrigins, logger)
	return app, nil
}

func (app *BackendApp) Ping(ctx context.Context) error {
	if err := app.thumbnailWorker.Ping(); err != nil {
		return err
	}
	if err := app.thumbnailDispatcher.Ping(); err != nil {
		return err
	}
	if err := app.chatWorker.Ping(); err != nil {
		return err
	}
	if err := app.chatDispatcher.Ping(); err != nil {
		return err
	}
	if err := app.aiWorker.Ping(); err != nil {
		return err
	}
	if err := app.aiDispatcher.Ping(); err != nil {
		return err
	}
	if err := app.paperlessWorker.Ping(); err != nil {
		return err
	}
	if err := app.paperlessDispatcher.Ping(); err != nil {
		return err
	}
	if err := app.realtime.Ping(ctx); err != nil {
		return err
	}
	if err := app.emailWorker.Ping(); err != nil {
		return err
	}
	if err := app.emailDispatcher.Ping(); err != nil {
		return err
	}
	if err := app.worker.Ping(); err != nil {
		return err
	}
	if err := app.source.Ping(ctx); err != nil {
		return fmt.Errorf("PostgreSQL readiness: %w", err)
	}
	if err := app.temporal.Ping(ctx); err != nil {
		return err
	}
	if err := app.documents.Ping(ctx); err != nil {
		return err
	}
	if err := app.dispatcher.Ping(); err != nil {
		return err
	}
	return app.worker.Ping()
}

func (app *BackendApp) FatalErrors() <-chan error { return app.fatal }

func (app *BackendApp) DrainRealtime() {
	if app.realtime != nil {
		app.realtime.Drain()
	}
}

func (app *BackendApp) Close() {
	app.closeOnce.Do(func() {
		if app.realtime != nil {
			app.realtime.Close()
		}
		app.cancel()
		app.listeners.Wait()
		if app.chatDispatcher != nil {
			app.chatDispatcher.Close()
		}
		if app.chatWorker != nil {
			app.chatWorker.Close()
		}
		if app.paperlessDispatcher != nil {
			app.paperlessDispatcher.Close()
		}
		if app.paperlessWorker != nil {
			app.paperlessWorker.Close()
		}
		app.emailDispatcher.Close()
		app.emailWorker.Close()
		app.dispatcher.Close()
		if app.aiDispatcher != nil {
			app.aiDispatcher.Close()
		}
		if app.aiWorker != nil {
			app.aiWorker.Close()
		}
		if app.thumbnailDispatcher != nil {
			app.thumbnailDispatcher.Close()
		}
		if app.thumbnailWorker != nil {
			app.thumbnailWorker.Close()
		}
		app.worker.Close()
		app.temporal.Close()
		app.source.Close()
	})
}
