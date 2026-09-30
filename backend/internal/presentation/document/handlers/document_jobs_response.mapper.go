package handlers

import (
	"sort"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func documentJobResponseMapper(v domain.DocumentJobHistory) contract.DocumentJob {
	var method *contract.DocumentJobExtractionMethod
	if v.ExtractionMethod != "" {
		value := contract.DocumentJobExtractionMethod(v.ExtractionMethod)
		method = &value
	}
	var configuration *contract.DocumentProcessingConfigurationSnapshot
	if v.Configuration != nil {
		value := documentConfigurationSnapshotResponseMapper(*v.Configuration)
		configuration = &value
	}
	var textSource *contract.DocumentJobTextSource
	if v.TextSource != nil {
		value := contract.DocumentJobTextSource(*v.TextSource)
		textSource = &value
	}
	return contract.DocumentJob{InvoiceClassification: documentInvoiceClassificationResponseMapper(v.InvoiceDecision, v.InvoiceDecisionReason, v.InvoiceClassificationPass, v.InvoiceInputCharacters, v.InvoiceSourceCharacters), RendererRevision: v.RendererRevision, Pipeline: contract.DocumentJobPipeline(v.Pipeline), PipelineVersion: new(v.PipelineVersion), Attempt: v.Attempt, ExtractionMethod: method, Id: uuid.MustParse(v.ID), DocumentId: uuid.MustParse(v.DocumentID), DocumentTitle: v.DocumentTitle, Generation: v.Generation, Reason: contract.DocumentJobReason(v.Reason), Status: contract.DocumentJobStatus(v.Status), Stage: contract.DocumentJobStage(v.Stage), ConfigurationRevision: v.ConfigurationRevision, ConfigurationFingerprint: v.ConfigurationFingerprint, Configuration: configuration, TextSource: textSource, CreatedAt: v.CreatedAt, StartedAt: v.StartedAt, FinishedAt: v.FinishedAt, UpdatedAt: v.UpdatedAt, FailureCode: v.FailureCode, IsCurrent: v.IsCurrent, DocumentDeleted: v.DocumentDeleted}
}

func documentReindexBatchResponseMapper(v domain.DocumentReindexBatch) contract.DocumentReindexBatch {
	return contract.DocumentReindexBatch{Id: uuid.MustParse(v.ID), Scope: contract.DocumentReindexBatchScope(v.Scope), Reason: contract.DocumentReindexBatchReason(v.Reason), Status: contract.DocumentReindexBatchStatus(v.Status), ConfigurationRevision: v.ConfigurationRevision, ConfigurationFingerprint: v.ConfigurationFingerprint, CreatedAt: v.CreatedAt, FinishedAt: v.FinishedAt, EnumerationComplete: v.EnumerationComplete, Discovered: v.Discovered, Waiting: v.Waiting, Running: v.Running, Succeeded: v.Succeeded, Failed: v.Failed, Skipped: v.Skipped, Superseded: v.Superseded}
}

func documentConfigurationSnapshotResponseMapper(c domain.DocumentProcessingConfiguration) contract.DocumentProcessingConfigurationSnapshot {
	weights := make([]contract.DocumentProcessingWeight, 0, len(c.Weights))
	for _, w := range c.Weights {
		weights = append(weights, contract.DocumentProcessingWeight{Name: w.Name, Sha256: w.SHA256})
	}
	sort.Slice(weights, func(i, j int) bool { return weights[i].Name < weights[j].Name })
	enabled, model := c.LLM.Enabled, c.LLM.Defaults().Model
	return contract.DocumentProcessingConfigurationSnapshot{PropertyExtractionEnabled: &enabled, PropertyExtractionModel: &model, InvoiceExtractionEnabled: new(c.LLM.InvoiceExtractionEnabled()), InvoiceExtractionModel: &model, Revision: c.Revision, Language: contract.DocumentProcessingConfigurationSnapshotLanguage(c.Language), Segmentation: contract.DocumentProcessingConfigurationSnapshotSegmentation(c.Segmentation), OcrEngine: c.Engine, OcrVersion: c.EngineVersion, OcrModel: "tessdata_fast@65727574dfcd264acbb0c3e07860e4e9e9b22185", OcrWeights: weights, EmbeddingModel: c.EmbeddingModel, EmbeddingDigest: c.EmbeddingDigest, EmbeddingDimensions: c.Dimensions, Fingerprint: c.Fingerprint, ManifestRevision: c.ManifestRevision, ExtractionRevision: c.ExtractionRevision, ChunkingRevision: c.ChunkingRevision, EmbeddingInputRevision: c.EmbeddingInputRevision, IndexingRevision: c.IndexingRevision}
}
