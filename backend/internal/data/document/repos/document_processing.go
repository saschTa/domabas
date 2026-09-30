package repos

import (
	"context"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
)

type DocumentProcessingSource interface {
	AIRetryFacts(context.Context, m.DocumentActor, string, string) (m.DocumentAIRetryFacts, error)
	AIRetryRecord(context.Context, m.DocumentActor, string, m.DocumentAIRetryCommand) (r.DocumentAIProcessingRecord, error)
	NamespaceConfigurationRecord(context.Context, m.DocumentActor) (r.DocumentConfigurationRecord, error)
	SearchConfigurationRecord(context.Context, m.DocumentActor) (r.DocumentConfigurationRecord, error)
	JobsRecord(context.Context, m.DocumentActor, m.DocumentProcessingPageInput, m.DocumentJobProjection) (r.DocumentJobPageRecord, error)
	JobHistoryRecord(context.Context, m.DocumentActor, string, m.DocumentJobProjection) (r.DocumentJobHistoryRecord, error)
	BatchesRecord(context.Context, m.DocumentActor, bool, m.DocumentProcessingPageInput) (r.DocumentReindexBatchPageRecord, error)
	BatchRecord(context.Context, m.DocumentActor, bool, string) (r.DocumentReindexBatchRecord, error)
	ReindexStartFacts(context.Context, m.DocumentActor, bool, string) (m.DocumentReindexStartFacts, error)
	CreateBatchRecord(context.Context, m.DocumentActor, bool, m.DocumentReindexStartCommand) (r.DocumentReindexBatchRecord, error)
}

func (rp *DocumentIngestionRepository) NamespaceConfiguration(ctx context.Context, a m.DocumentActor) (m.DocumentProcessingConfiguration, error) {
	v, e := rp.source.NamespaceConfigurationRecord(ctx, a)
	return documentConfigurationRecordToDomainMapper(v), e
}
func (rp *DocumentIngestionRepository) SearchConfiguration(ctx context.Context, a m.DocumentActor) (m.DocumentProcessingConfiguration, error) {
	v, e := rp.source.SearchConfigurationRecord(ctx, a)
	return documentConfigurationRecordToDomainMapper(v), e
}

func (rp *DocumentIngestionRepository) Jobs(ctx context.Context, a m.DocumentActor, input m.DocumentProcessingPageInput, projections ...m.DocumentJobProjection) (m.DocumentJobPage, error) {
	projection := m.DocumentJobProjection{}
	if len(projections) > 0 {
		projection = projections[0]
	}
	v, e := rp.source.JobsRecord(ctx, a, input, projection)
	out := m.DocumentJobPage{Items: []m.DocumentJobHistory{}, NextCursor: v.NextCursor}
	if e != nil {
		return out, e
	}
	for _, count := range v.Counts {
		out.Counts = append(out.Counts, m.DocumentJobCount(count))
	}
	for _, item := range v.Items {
		mapped, e := documentJobHistoryRecordToDomainMapper(item)
		if e != nil {
			return out, e
		}
		out.Items = append(out.Items, mapped)
	}
	return out, nil
}
func (rp *DocumentIngestionRepository) JobHistory(ctx context.Context, a m.DocumentActor, id string, projections ...m.DocumentJobProjection) (m.DocumentJobHistory, error) {
	projection := m.DocumentJobProjection{}
	if len(projections) > 0 {
		projection = projections[0]
	}
	v, e := rp.source.JobHistoryRecord(ctx, a, id, projection)
	if e != nil {
		return m.DocumentJobHistory{}, e
	}
	return documentJobHistoryRecordToDomainMapper(v)
}
func (rp *DocumentIngestionRepository) Batches(ctx context.Context, a m.DocumentActor, system bool, input m.DocumentProcessingPageInput) (m.DocumentReindexBatchPage, error) {
	v, e := rp.source.BatchesRecord(ctx, a, system, input)
	out := m.DocumentReindexBatchPage{Items: []m.DocumentReindexBatch{}, NextCursor: v.NextCursor}
	for _, count := range v.Counts {
		out.Counts = append(out.Counts, m.DocumentReindexStatusCount(count))
	}
	for _, item := range v.Items {
		out.Items = append(out.Items, m.DocumentReindexBatch(item))
	}
	return out, e
}
func (rp *DocumentIngestionRepository) Batch(ctx context.Context, a m.DocumentActor, system bool, id string) (m.DocumentReindexBatch, error) {
	v, e := rp.source.BatchRecord(ctx, a, system, id)
	return m.DocumentReindexBatch(v), e
}
func (rp *DocumentIngestionRepository) CreateBatch(ctx context.Context, a m.DocumentActor, system bool, input m.DocumentReindexStartCommand) (m.DocumentReindexBatch, error) {
	v, e := rp.source.CreateBatchRecord(ctx, a, system, input)
	return m.DocumentReindexBatch(v), e
}

func (rp *DocumentIngestionRepository) AIRetryFacts(ctx context.Context, a m.DocumentActor, id, request string) (m.DocumentAIRetryFacts, error) {
	return rp.source.AIRetryFacts(ctx, a, id, request)
}
func (rp *DocumentIngestionRepository) RetryAI(ctx context.Context, a m.DocumentActor, id string, input m.DocumentAIRetryCommand) (m.DocumentAIProcessing, error) {
	v, e := rp.source.AIRetryRecord(ctx, a, id, input)
	return m.DocumentAIProcessing(v), e
}

func (rp *DocumentIngestionRepository) ReindexStartFacts(ctx context.Context, a m.DocumentActor, system bool, request string) (m.DocumentReindexStartFacts, error) {
	return rp.source.ReindexStartFacts(ctx, a, system, request)
}
