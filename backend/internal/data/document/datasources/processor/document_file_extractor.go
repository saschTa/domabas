package processor

import (
	"context"
	"fmt"

	"github.com/tetratelabs/wazero"
)

type DocumentFileExtractor struct {
	compilationCache wazero.CompilationCache
}

func NewDocumentFileExtractor(cacheDirectory string) (*DocumentFileExtractor, error) {
	cache := wazero.NewCompilationCache()
	if cacheDirectory != "" {
		var err error
		cache, err = wazero.NewCompilationCacheWithDir(cacheDirectory)
		if err != nil {
			return nil, fmt.Errorf("open PDF compilation cache: %w", err)
		}
	}
	return &DocumentFileExtractor{compilationCache: cache}, nil
}

func (e *DocumentFileExtractor) Close() error {
	return e.compilationCache.Close(context.Background())
}

func (e *DocumentFileExtractor) WarmPDF(ctx context.Context) error {
	pool, err := e.newPDFPool(ctx)
	if err != nil {
		return fmt.Errorf("compile PDF engine: %w", err)
	}
	return pool.Close()
}
