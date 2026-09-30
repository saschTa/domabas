package document

import (
	"context"
	"io"
	"net/http"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/processor"
	"github.com/domabas/domabas/backend/internal/data/document/repos"
	processorhandlers "github.com/domabas/domabas/backend/internal/presentation/document/handlers/processor"
)

type DocumentProcessorConfig struct {
	ModelCacheRoot, OllamaCacheRoot, OllamaURL string
	OllamaMaxQueue                             int
}
type DocumentProcessorContainer struct {
	source  *processor.LocalDocumentProcessorDataSource
	handler http.Handler
}

func NewDocumentProcessorContainer(ctx context.Context, configuration DocumentProcessorConfig) (*DocumentProcessorContainer, error) {
	source, err := processor.NewLocalDocumentProcessorDataSource(ctx, configuration.ModelCacheRoot, configuration.OllamaCacheRoot, configuration.OllamaURL, configuration.OllamaMaxQueue)
	if err != nil {
		return nil, err
	}
	return &DocumentProcessorContainer{source: source, handler: processorhandlers.NewDocumentProcessorHandler(repos.NewDocumentProcessorRepository(source), repos.NewDocumentThumbnailProcessorRepository(source))}, nil
}
func (container *DocumentProcessorContainer) Handler() http.Handler { return container.handler }
func (container *DocumentProcessorContainer) Close()                { container.source.Close() }
func RunProcessorWorker(ctx context.Context, args []string, input io.Reader, output io.Writer) error {
	return processor.RunWorker(ctx, args, input, output)
}
