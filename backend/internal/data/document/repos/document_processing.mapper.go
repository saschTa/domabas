package repos

import (
	"encoding/json"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func documentJobHistoryRecordToDomainMapper(v r.DocumentJobHistoryRecord) (m.DocumentJobHistory, error) {
	var config *m.DocumentProcessingConfiguration
	if len(v.Configuration) > 0 {
		var record r.DocumentConfigurationRecord
		if e := json.Unmarshal(v.Configuration, &record); e != nil {
			return m.DocumentJobHistory{}, e
		}
		value := documentConfigurationRecordToDomainMapper(record)
		config = &value
	}
	return m.DocumentJobHistory{InvoiceDecision: v.InvoiceDecision, InvoiceDecisionReason: v.InvoiceDecisionReason, InvoiceClassificationPass: v.InvoiceClassificationPass, InvoiceInputCharacters: v.InvoiceInputCharacters, InvoiceSourceCharacters: v.InvoiceSourceCharacters, Pipeline: v.Pipeline, RendererRevision: v.RendererRevision, PipelineVersion: v.PipelineVersion, Attempt: v.Attempt, ExtractionMethod: v.ExtractionMethod, ExtractionEngine: v.ExtractionEngine, ExtractionEngineVersion: v.ExtractionEngineVersion, ID: v.ID, DocumentID: v.DocumentID, DocumentTitle: v.DocumentTitle, Generation: v.Generation, Reason: v.Reason, Status: v.Status, Stage: v.Stage, ConfigurationRevision: v.ConfigurationRevision, ConfigurationFingerprint: v.ConfigurationFingerprint, Configuration: config, TextSource: v.TextSource, CreatedAt: v.CreatedAt, UpdatedAt: v.UpdatedAt, StartedAt: v.StartedAt, FinishedAt: v.FinishedAt, FailureCode: v.FailureCode, IsCurrent: v.IsCurrent, DocumentDeleted: v.DocumentDeleted}, nil
}
