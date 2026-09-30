package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentIngestionRecordToDomainMapper(d r.DocumentRecord) m.Document {
	result := m.Document{ID: d.ID, Title: d.Title, Description: d.Description, CreatedAt: d.CreatedAt, Kind: d.Kind, Sender: d.Sender, DocumentDate: d.DocumentDate, Subject: d.Subject, MessageID: d.MessageID, Tags: d.Tags, Recipients: d.Recipients, CC: d.CC, BCC: d.BCC}
	if d.Thumbnail != nil {
		value := m.DocumentThumbnail(*d.Thumbnail)
		result.Thumbnail = &value
	}
	if d.File != nil {
		value := m.DocumentFile(*d.File)
		result.File = &value
	}
	if d.Processing != nil {
		value := documentProcessingRecordToDomainMapper(*d.Processing)
		result.Processing = &value
	}
	return result
}

func documentReferenceRecordToDomainMapper(r r.DocumentReferenceRecord) m.DocumentFileReference {
	return m.DocumentFileReference{AccountID: r.AccountID, UploaderID: r.UploaderID, DocumentID: r.DocumentID, Location: r.Location, File: m.DocumentFile(r.File)}
}

func documentConfigurationRecordToDomainMapper(c r.DocumentConfigurationRecord) m.DocumentProcessingConfiguration {
	result := m.DocumentProcessingConfiguration{LLM: m.DocumentLLMConfiguration(c.LLM), ManifestRevision: c.ManifestRevision, Fingerprint: c.Fingerprint, ExtractionRevision: c.ExtractionRevision, ChunkingRevision: c.ChunkingRevision, EmbeddingInputRevision: c.EmbeddingInputRevision, IndexingRevision: c.IndexingRevision, DashboardURL: c.DashboardURL, AutomaticBatchID: c.AutomaticBatchID, ExpectedRevision: c.ExpectedRevision, Revision: c.Revision, Language: c.Language, Segmentation: c.Segmentation, Engine: c.Engine, EngineVersion: c.EngineVersion, EmbeddingModel: c.EmbeddingModel, EmbeddingDigest: c.EmbeddingDigest, Dimensions: c.Dimensions, Ready: c.Ready, Weights: make([]m.DocumentWeight, 0, len(c.Weights))}
	for _, w := range c.Weights {
		result.Weights = append(result.Weights, m.DocumentWeight(w))
	}
	if c.Scheduling != nil {
		result.Scheduling = new(m.DocumentProcessingScheduling(*c.Scheduling))
	}
	return result.WithLegacyIdentity()
}

func documentProcessingRecordToDomainMapper(p r.DocumentProcessingRecord) m.DocumentProcessing {
	var ai *m.DocumentAIProcessing
	if p.AI != nil {
		value := m.DocumentAIProcessing(*p.AI)
		ai = &value
	}
	return m.DocumentProcessing{AI: ai, ExtractionMethod: p.ExtractionMethod, ExtractionEngine: p.ExtractionEngine, ExtractionEngineVersion: p.ExtractionEngineVersion, State: p.State, Stage: p.Stage, FailureCode: p.FailureCode, Generation: p.Generation, ConfigurationRevision: p.ConfigurationRevision, UpdatedAt: p.UpdatedAt, Configuration: documentConfigurationRecordToDomainMapper(p.Configuration)}
}

func documentWorkRecordToDomainMapper(w r.DocumentWorkRecord) m.DocumentProcessingWork {
	result := m.DocumentProcessingWork{Eligible: w.Eligible, UnlimitedInference: w.UnlimitedInference, SplitPipeline: w.SplitPipeline, EmbeddingsComplete: w.EmbeddingsComplete, ManualText: w.ManualText, Revision: w.Revision, Job: m.DocumentJob(w.Job), Reference: documentReferenceRecordToDomainMapper(w.Reference), Configuration: documentConfigurationRecordToDomainMapper(w.Configuration), State: w.State, Stage: w.Stage, Chunks: make([]m.DocumentChunk, 0, len(w.Chunks))}
	for _, c := range w.Chunks {
		result.Chunks = append(result.Chunks, m.DocumentChunk(c))
	}
	return result
}

func documentSearchRecordToDomainMapper(s r.DocumentSearchRecord) m.DocumentSearchResults {
	result := m.DocumentSearchResults{Total: s.Total, Items: make([]m.DocumentSearchResult, 0, len(s.Items)), NextCursor: s.NextCursor}
	for _, item := range s.Items {
		doc := item.Document
		summary := m.SearchDocument{ID: doc.ID, Title: doc.Title, Kind: doc.Kind, DocumentDate: doc.DocumentDate, ProcessingState: doc.ProcessingState, Tags: doc.Tags, CreatedAt: doc.CreatedAt}
		if doc.Thumbnail != nil {
			value := m.DocumentThumbnail(*doc.Thumbnail)
			summary.Thumbnail = &value
		}
		if doc.Original != nil {
			summary.Original = &m.DocumentSearchOriginal{SHA256: doc.Original.SHA256, MediaType: doc.Original.MediaType, Size: doc.Original.Size}
		}
		result.Items = append(result.Items, m.DocumentSearchResult{Document: summary, Score: item.Score, Snippet: item.Snippet})
	}
	return result
}

func documentLeaseRecordToDomainMapper(l r.DocumentLeaseRecord) m.DocumentOutboxLease {
	return m.DocumentOutboxLease{SplitPipeline: l.SplitPipeline, UnlimitedInference: l.UnlimitedInference, WorkflowID: l.WorkflowID, TaskQueue: l.TaskQueue, RunID: l.RunID, PermitEnd: l.PermitEnd, ID: l.ID, LeaseToken: l.LeaseToken, Job: m.DocumentJob(l.Job), DeliveryDeadline: l.DeliveryDeadline, ConfigurationRevision: l.ConfigurationRevision}
}

func documentPendingRecordToDomainMapper(p r.DocumentPendingRecord) m.DocumentPendingJob {
	return m.DocumentPendingJob{SplitPipeline: p.SplitPipeline, UnlimitedInference: p.UnlimitedInference, LeaseToken: p.LeaseToken, TaskQueue: p.TaskQueue, LatestPermitEnd: p.LatestPermitEnd, Legacy: p.Legacy, Job: m.DocumentJob(p.Job), WorkflowID: p.WorkflowID, RunID: p.RunID, State: p.State, DeliveryDeadline: p.DeliveryDeadline, ProcessingDeadline: p.ProcessingDeadline}
}
