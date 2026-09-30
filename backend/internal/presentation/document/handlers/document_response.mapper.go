package handlers

import (
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func documentResponseMapper(doc domain.Document) contract.Document {
	kind := contract.DocumentKind(doc.Kind)
	if kind == "" {
		kind = "document"
	}
	tags, recipients, cc, bcc := documentStringSliceMapper(doc.Tags), documentStringSliceMapper(doc.Recipients), documentStringSliceMapper(doc.CC), documentStringSliceMapper(doc.BCC)
	response := contract.Document{Id: uuid.MustParse(doc.ID), Title: doc.Title, Description: doc.Description, CreatedAt: doc.CreatedAt, Kind: &kind, Tags: &tags, Sender: documentOptionalStringMapper(doc.Sender), Recipients: &recipients, Cc: &cc, Bcc: &bcc, DocumentDate: documentOptionalStringMapper(doc.DocumentDate), Subject: documentOptionalStringMapper(doc.Subject), MessageId: documentOptionalStringMapper(doc.MessageID)}
	response.Thumbnail = documentThumbnailResponseMapper(doc.Thumbnail)
	if doc.File != nil {
		file := doc.File
		response.File = &contract.DocumentFile{OriginalFilename: file.OriginalFilename, MediaType: contract.DocumentFileMediaType(file.MediaType), Size: file.Size, Sha256: file.SHA256, IngestedAt: file.IngestedAt, UploaderId: uuid.MustParse(file.UploaderID)}
	}
	if doc.Processing != nil {
		processing := documentProcessingResponseMapper(*doc.Processing)
		response.Processing = &processing
	}
	return response
}

func documentProcessingResponseMapper(processing domain.DocumentProcessing) contract.DocumentProcessing {
	c := processing.Configuration
	var method *contract.DocumentProcessingExtractionMethod
	engine, version, model := "", "", ""
	if processing.ExtractionMethod != "" {
		value := contract.DocumentProcessingExtractionMethod(processing.ExtractionMethod)
		method = &value
		engine, version = processing.ExtractionEngine, processing.ExtractionEngineVersion
		if processing.ExtractionMethod == "ocr" {
			model = "tessdata_fast@65727574dfcd264acbb0c3e07860e4e9e9b22185"
		}
	}
	var ai *contract.DocumentAIProcessing
	if processing.AI != nil {
		v := documentAIResponseMapper(*processing.AI)
		ai = &v
	}
	return contract.DocumentProcessing{Ai: ai, ExtractionMethod: method, State: contract.DocumentProcessingState(processing.State), Stage: contract.DocumentProcessingStage(processing.Stage), Generation: processing.Generation, ConfigurationRevision: processing.ConfigurationRevision, UpdatedAt: processing.UpdatedAt, FailureCode: documentOptionalStringMapper(processing.FailureCode), OcrEngine: engine, OcrVersion: version, OcrModel: model, OcrLanguage: contract.DocumentProcessingOcrLanguage(c.Language), OcrSegmentation: contract.DocumentProcessingOcrSegmentation(c.Segmentation), EmbeddingModel: c.EmbeddingModel, EmbeddingDigest: c.EmbeddingDigest, EmbeddingDimensions: c.Dimensions}
}

func documentConfigurationResponseMapper(c domain.DocumentProcessingConfiguration) contract.DocumentProcessingConfiguration {
	v := documentConfigurationSnapshotResponseMapper(c)
	var batch *uuid.UUID
	if c.AutomaticBatchID != "" {
		id := uuid.MustParse(c.AutomaticBatchID)
		batch = &id
	}
	llm := c.LLM.Defaults()
	return contract.DocumentProcessingConfiguration{Scheduling: documentSchedulingResponseMapper(c.Scheduling), Llm: &contract.LLMConfiguration{PropertyThinkingEnabled: new(llm.PropertyThinkingEnabled), InvoiceThinkingEnabled: new(llm.InvoiceThinkingEnabled), LmStudioCompatibility: new(llm.LMStudioCompatibility), ContextLength: llm.RequestedContextLength(), Enabled: llm.Enabled, InvoiceEnabled: llm.InvoiceExtractionEnabled(), Provider: contract.LLMConfigurationProvider(llm.Provider), Model: llm.Model, BaseUrl: llm.BaseURL, CredentialConfigured: llm.CredentialID != ""}, AutomaticBatchId: batch, DashboardUrl: documentOptionalStringMapper(c.DashboardURL), OcrWeights: v.OcrWeights, Fingerprint: c.Fingerprint, ManifestRevision: c.ManifestRevision, ExtractionRevision: c.ExtractionRevision, ChunkingRevision: c.ChunkingRevision, EmbeddingInputRevision: c.EmbeddingInputRevision, IndexingRevision: c.IndexingRevision, Revision: c.Revision, Language: contract.DocumentProcessingConfigurationLanguage(c.Language), Segmentation: contract.DocumentProcessingConfigurationSegmentation(c.Segmentation), OcrEngine: c.Engine, OcrVersion: c.EngineVersion, OcrModel: "tessdata_fast@65727574dfcd264acbb0c3e07860e4e9e9b22185", EmbeddingModel: c.EmbeddingModel, EmbeddingDigest: c.EmbeddingDigest, EmbeddingDimensions: c.Dimensions, Ready: c.Ready, Languages: []contract.DocumentProcessingConfigurationLanguages{"eng", "deu", "eng+deu"}, Segmentations: []contract.DocumentProcessingConfigurationSegmentations{"auto", "single_block"}}
}

func documentOptionalStringMapper(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func documentStringSliceMapper(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

func documentAIResponseMapper(v domain.DocumentAIProcessing) contract.DocumentAIProcessing {
	return contract.DocumentAIProcessing{InvoiceClassification: documentInvoiceClassificationResponseMapper(v.InvoiceDecision, v.InvoiceDecisionReason, v.InvoiceClassificationPass, v.InvoiceInputCharacters, v.InvoiceSourceCharacters), JobId: uuid.MustParse(v.JobID), Attempt: v.Attempt, Status: contract.DocumentAIProcessingStatus(v.Status), Stage: contract.DocumentAIProcessingStage(v.Stage), ConfigurationRevision: v.ConfigurationRevision, UpdatedAt: v.UpdatedAt, StartedAt: v.StartedAt, FinishedAt: v.FinishedAt, FailureCode: v.FailureCode}
}

func documentThumbnailResponseMapper(v *domain.DocumentThumbnail) *contract.DocumentThumbnail {
	if v == nil {
		return nil
	}
	return &contract.DocumentThumbnail{SourceSha256: v.SourceSHA256, Sha256: v.SHA256, MediaType: contract.DocumentThumbnailMediaType(v.MediaType), Size: v.Size, Width: v.Width, Height: v.Height, RendererRevision: v.RendererRevision}
}
