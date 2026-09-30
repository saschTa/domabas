package interfaces

import (
	"context"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentPropertyRepository interface {
	Work(context.Context, m.DocumentJob) (m.DocumentPropertyWork, error)
	Credential(context.Context, string) (string, error)
	Save(context.Context, m.DocumentPropertyWork, m.DocumentMetadata) error
}

type DocumentPropertyExtractor interface {
	ExtractProperties(context.Context, m.DocumentLLMConfiguration, string, string) (m.DocumentMetadata, error)
}
