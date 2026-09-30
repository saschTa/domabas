package repos

import (
	"context"
	"io"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	ports "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentProcessorSource interface {
	UnlockPDF(context.Context, io.Reader, string) ([]byte, error)
	Extract(context.Context, io.Reader, string, records.DocumentProcessorOptions) (records.DocumentExtractionResult, error)
	Embed(context.Context, records.DocumentEmbeddingSpaceRecord, string, []string) (records.DocumentEmbeddingResult, error)
	Ready(context.Context) error
}
type DocumentProcessorRepository struct{ source DocumentProcessorSource }

var _ ports.DocumentProcessor = (*DocumentProcessorRepository)(nil)

func NewDocumentProcessorRepository(source DocumentProcessorSource) *DocumentProcessorRepository {
	return &DocumentProcessorRepository{source: source}
}
func (processor *DocumentProcessorRepository) Extract(ctx context.Context, reader io.Reader, mediaType string, configuration domain.DocumentProcessingConfiguration) (domain.DocumentExtraction, error) {
	configuration = configuration.WithLegacyIdentity()
	if _, err := configuration.ExtractionIdentity(mediaType); err != nil {
		return domain.DocumentExtraction{}, err
	}
	result, err := processor.source.Extract(ctx, reader, mediaType, records.DocumentProcessorOptions{ExtractionRevision: configuration.WithLegacyIdentity().ExtractionRevision, Language: configuration.Language, Segmentation: configuration.Segmentation})
	if err != nil {
		return domain.DocumentExtraction{}, adapterError(err)
	}
	extraction := domain.DocumentExtraction{InvoiceFailureCode: result.InvoiceFailureCode, InvoiceXML: result.InvoiceXML, ExtractionRevision: result.ExtractionRevision, Text: result.Text, Pages: result.Pages, Engine: result.Engine, EngineVersion: result.EngineVersion, Weights: make([]domain.DocumentWeight, len(result.Weights))}
	for i, weight := range result.Weights {
		extraction.Weights[i] = domain.DocumentWeight{Name: weight.Name, SHA256: weight.SHA256}
	}
	if err := configuration.ValidateExtraction(mediaType, extraction); err != nil {
		return domain.DocumentExtraction{}, err
	}
	return extraction, nil
}
func (processor *DocumentProcessorRepository) Embed(ctx context.Context, space domain.DocumentEmbeddingSpace, purpose string, inputs []string) (domain.DocumentEmbedding, error) {
	if !space.Supported() {
		return domain.DocumentEmbedding{}, domain.DocumentProcessingError{Code: "configuration_unavailable"}
	}
	result, err := processor.source.Embed(ctx, records.DocumentEmbeddingSpaceRecord(space), purpose, inputs)
	if err != nil {
		return domain.DocumentEmbedding{}, adapterError(err)
	}
	if domain.DocumentEmbeddingSpace(result.Space) != space || result.Model != space.Model || result.Digest != space.Digest || len(result.Vectors) != len(inputs) {
		return domain.DocumentEmbedding{}, domain.DocumentProcessingError{Code: "processing_failed"}
	}
	vectors := make([][]float64, len(result.Vectors))
	for i, vector := range result.Vectors {
		vectors[i], err = domain.NormalizeVector(vector)
		if err != nil {
			return domain.DocumentEmbedding{}, err
		}
	}
	return domain.DocumentEmbedding{Space: space, Model: result.Model, Digest: result.Digest, Vectors: vectors}, nil
}
func (processor *DocumentProcessorRepository) Ready(ctx context.Context) error {
	return adapterError(processor.source.Ready(ctx))
}

func (processor *DocumentProcessorRepository) UnlockPDF(ctx context.Context, reader io.Reader, password string) ([]byte, error) {
	result, err := processor.source.UnlockPDF(ctx, reader, password)
	return result, adapterError(err)
}
