package repos

import (
	"context"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentPropertySource interface {
	PropertyWorkRecord(context.Context, m.DocumentJob) (r.DocumentPropertyWorkRecord, error)
	PropertyCredential(context.Context, string) (string, error)
	SaveProperties(context.Context, m.DocumentPropertyWork, m.DocumentMetadata) error
}

type DocumentPropertyRepository struct{ source DocumentPropertySource }

func NewDocumentPropertyRepository(source DocumentPropertySource) *DocumentPropertyRepository {
	return &DocumentPropertyRepository{source}
}
func (r *DocumentPropertyRepository) Work(ctx context.Context, job m.DocumentJob) (m.DocumentPropertyWork, error) {
	w, err := r.source.PropertyWorkRecord(ctx, job)
	return m.DocumentPropertyWork{Eligible: w.Eligible, Job: job, Configuration: m.DocumentLLMConfiguration(w.Configuration), Stage: w.Stage, Text: w.Text, Revision: w.Revision, MetadataRevision: w.MetadataRevision, Metadata: documentPropertyMetadataMapper(w.Metadata)}, err
}
func (r *DocumentPropertyRepository) Credential(ctx context.Context, id string) (string, error) {
	return r.source.PropertyCredential(ctx, id)
}
func (r *DocumentPropertyRepository) Save(ctx context.Context, work m.DocumentPropertyWork, values m.DocumentMetadata) error {
	return r.source.SaveProperties(ctx, work, values)
}

type DocumentPropertyExtractionSource interface {
	Extract(context.Context, string, string, string, string, string, bool, bool, ...int) (r.DocumentExtractedProperties, error)
}
type DocumentPropertyExtractionRepository struct {
	source DocumentPropertyExtractionSource
}

func NewDocumentPropertyExtractionRepository(source DocumentPropertyExtractionSource) *DocumentPropertyExtractionRepository {
	return &DocumentPropertyExtractionRepository{source}
}
func (e *DocumentPropertyExtractionRepository) ExtractProperties(ctx context.Context, c m.DocumentLLMConfiguration, key, text string) (m.DocumentMetadata, error) {
	c = c.Defaults()
	v, err := e.source.Extract(ctx, c.Provider, c.Model, c.BaseURL, key, text, c.LMStudioCompatibility, c.PropertyThinkingEnabled, c.RequestedContextLength())
	return m.DocumentMetadata{Description: v.Description, Tags: v.Tags, Sender: v.Sender, Recipients: v.Recipients, DocumentDate: v.DocumentDate, Subject: v.Subject}, err
}
