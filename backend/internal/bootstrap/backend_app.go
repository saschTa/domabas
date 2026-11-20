package bootstrap

import (
	"context"
	"fmt"
	chatcontainer "github.com/domabas/domabas/backend/internal/bootstrap/chat"
	schedulercontainer "github.com/domabas/domabas/backend/internal/bootstrap/scheduler"
	"github.com/domabas/domabas/backend/internal/data/jobs"
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
	"github.com/domabas/domabas/backend/internal/data/postgres"
	documenthandlers "github.com/domabas/domabas/backend/internal/presentation/document/handlers"
	emailhandlers "github.com/domabas/domabas/backend/internal/presentation/email/handlers"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	identityhandlers "github.com/domabas/domabas/backend/internal/presentation/identity/handlers"
	invoicehandlers "github.com/domabas/domabas/backend/internal/presentation/invoice/handlers"
	paperlesshandlers "github.com/domabas/domabas/backend/internal/presentation/paperless/handlers"
)

type BackendApp struct {
	Handler   http.Handler
	source    *postgres.PostgresDataSource
	documents *documentcontainer.DocumentContainer
	realtime  *realtimecontainer.RealtimeContainer
	chat      *chatcontainer.ChatContainer
	executor  *jobs.NativeExecutor
	closeOnce sync.Once
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
	identities, err := identitycontainer.NewIdentityContainer(source.Database(), time.Now)
	if err != nil {

		source.Close()
		return nil, err
	}
	scheduler, err := schedulercontainer.NewSchedulerContainer(ctx, source.Database(), identities.Service(), config.EmbeddingQueueSize)
	if err != nil {

		source.Close()
		return nil, fmt.Errorf("initialize workload scheduler: %w", err)
	}
	documents, err := documentcontainer.NewDocumentContainer(ctx, source.Database(), identities.Service(), documentcontainer.DocumentOptions{Logger: logger, Scheduler: scheduler.Admission(), IngestionConcurrency: config.DocumentIngestionConcurrency, AIConcurrency: config.DocumentAIConcurrency, EmbeddingQueueSize: config.EmbeddingQueueSize, IngestionConcurrencyMode: config.DocumentIngestionConcurrencyMode, AIConcurrencyMode: config.DocumentAIConcurrencyMode, LLMCredentialKey: config.LLMCredentialKey, LLMCredentialKeyFile: config.LLMCredentialKeyFile, IngestionRoot: config.DocumentIngestionRoot, StorageRoot: config.DocumentStorageRoot, ProcessorURL: config.DocumentProcessorURL, DashboardURL: ""}, time.Now)
	if err != nil {

		source.Close()
		return nil, err
	}
	invoices := invoicecontainer.NewInvoiceService(source.Database(), identities.Service(), documents.LanguageModel(), documents.Credentials(), logger)
	keyFile := config.PaperlessCredentialKeyFile
	if keyFile == "" {
		keyFile = filepath.Join(config.DocumentStorageRoot, ".secrets", "paperless.key")
	}
	imports, err := paperlesscontainer.NewPaperlessJobsService(ctx, source.Database(), identities.Service(), config.PaperlessCredentialKey, keyFile, "native-paperless", documents.Ingestion(), scheduler.Admission())
	if err != nil {
		documents.Close()

		source.Close()
		return nil, err
	}
	emailKeyFile := config.EmailCredentialKeyFile
	if emailKeyFile == "" {
		emailKeyFile = filepath.Join(config.DocumentStorageRoot, ".secrets", "email.key")
	}
	emails, err := emailcontainer.NewEmailContainer(ctx, source.Database(), identities.Service(), documents.Importer(), emailcontainer.EmailOptions{Scheduler: scheduler.Admission(), CredentialKeys: config.EmailCredentialKeys, ActiveKeyID: config.EmailActiveKeyID, CredentialKeyFile: emailKeyFile, CAFile: config.EmailIMAPCAFile, AllowedHosts: config.EmailIMAPAllowedHosts}, time.Now)
	if err != nil {
		documents.Close()

		source.Close()
		return nil, fmt.Errorf("initialize email ingestion: %w", err)
	}
	app := &BackendApp{source: source, documents: documents}
	chatQueue := "native-chat"
	chat, err := chatcontainer.NewChatContainer(ctx, source.Database(), identities.Service(), scheduler.Admission(), config.DocumentStorageRoot, chatQueue)
	if err != nil {
		app.Close()
		return nil, fmt.Errorf("initialize chat: %w", err)
	}
	app.chat = chat
	app.realtime, err = realtimecontainer.NewRealtimeContainer(ctx, source.Database(), config.DatabaseURL, identities.Service(), identities.Authorizer(), config.CORSOrigins)
	if err != nil {
		app.Close()
		return nil, fmt.Errorf("initialize realtime: %w", err)
	}
	app.executor = jobs.NewNativeExecutor(source.Database(), config.DatabaseURL, logger)
	pipelines := nativePipelines{executor: app.executor, documents: documents, invoices: invoices, email: emails, chat: chat, paperless: imports, scheduler: scheduler}
	app.executor.Start(pipelines.poll)
	handler := httpapi.NewHTTPHandler(documenthandlers.NewDocumentHandler(documents.Service(), documents.Ingestion(), documents.Importer(), documents.Vocabulary(), logger).WithThumbnails(documents.Thumbnails()), identityhandlers.NewIdentityHandler(identities.Service(), identities.Activity(), logger), emailhandlers.NewEmailHandler(emails.Service(), logger), app, app.realtime.Handler(), invoicehandlers.NewInvoiceHandler(invoices, logger), paperlesshandlers.NewPaperlessHandler(imports)).WithChat(chathandlers.NewChatHandler(chat.Service())).WithScheduler(scheduler.Handler())
	app.Handler = httpapi.NewHTTPRouter(handler, transport.NewHTTPIdentityGuard(identities.Service(), identities.Authorizer()), config.CORSOrigins, logger)
	return app, nil
}

func (app *BackendApp) Ping(ctx context.Context) error {
	if err := app.executor.Ping(); err != nil {
		return err
	}
	if err := app.source.Ping(ctx); err != nil {
		return err
	}
	if err := app.realtime.Ping(ctx); err != nil {
		return err
	}
	return app.documents.Ping(ctx)
}
func (app *BackendApp) DrainRealtime() {
	if app.realtime != nil {
		app.realtime.Drain()
	}
}
func (app *BackendApp) Close() {
	app.closeOnce.Do(func() {
		if app.executor != nil {
			app.executor.Close()
		}
		if app.realtime != nil {
			app.realtime.Close()
		}
		if app.chat != nil {
			app.chat.Close()
		}
		app.documents.Close()
		app.source.Close()
	})
}
