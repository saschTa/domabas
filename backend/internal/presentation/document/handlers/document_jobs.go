package handlers

import (
	"context"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func pageInput(limit *int, cursor *string) (domain.DocumentProcessingPageInput, error) {
	v := domain.DocumentProcessingPageInput{Limit: 20}
	if limit != nil {
		v.Limit = *limit
	}
	if cursor != nil {
		v.Cursor = *cursor
		if v.Cursor == "" {
			return v, domain.DocumentValidationError{Message: "cursor must not be empty"}
		}
	}
	if v.Limit < 1 || v.Limit > 50 || len(v.Cursor) > 4096 {
		return v, domain.DocumentValidationError{Message: "invalid processing pagination"}
	}
	return v, nil
}
func (handler *DocumentHandler) GetNamespaceDocumentProcessing(ctx context.Context, _ contract.GetNamespaceDocumentProcessingRequestObject) (contract.GetNamespaceDocumentProcessingResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	c, e := handler.ingestion.NamespaceConfiguration(ctx, a)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.GetNamespaceDocumentProcessing200JSONResponse{Scheduling: documentSchedulingResponseMapper(c.Scheduling), Configuration: documentConfigurationSnapshotResponseMapper(c), Ready: c.Ready, Languages: []contract.DocumentProcessingPipelineLanguages{"eng", "deu", "eng+deu"}, Segmentations: []contract.DocumentProcessingPipelineSegmentations{"auto", "single_block"}}, nil
}
func (handler *DocumentHandler) GetDocumentJob(ctx context.Context, req contract.GetDocumentJobRequestObject) (contract.GetDocumentJobResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	v, e := handler.ingestion.JobHistory(ctx, a, req.JobId.String())
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.GetDocumentJob200JSONResponse(documentJobResponseMapper(v)), nil
}
func (handler *DocumentHandler) ListDocumentJobs(ctx context.Context, req contract.ListDocumentJobsRequestObject) (contract.ListDocumentJobsResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	input, e := pageInput(req.Params.Limit, req.Params.Cursor)
	input.ActiveOnly = req.Params.ActiveOnly != nil && *req.Params.ActiveOnly
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	if req.Params.Pipeline != nil {
		input.Pipeline = string(*req.Params.Pipeline)
	}
	if req.Params.Status != nil {
		input.Status = string(*req.Params.Status)
	}
	if req.Params.DocumentId != nil {
		input.DocumentID = req.Params.DocumentId.String()
	}
	v, e := handler.ingestion.Jobs(ctx, a, input)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	out := contract.DocumentJobPage{Counts: &contract.DocumentJobCounts{Groups: []contract.DocumentJobCount{}}, Items: []contract.DocumentJob{}, NextCursor: documentOptionalStringMapper(v.NextCursor)}
	for _, count := range v.Counts {
		out.Counts.Groups = append(out.Counts.Groups, contract.DocumentJobCount{Pipeline: contract.DocumentJobCountPipeline(count.Pipeline), Status: count.Status, Count: count.Count})
	}
	for _, item := range v.Items {
		out.Items = append(out.Items, documentJobResponseMapper(item))
	}
	return contract.ListDocumentJobs200JSONResponse(out), nil
}

func (handler *DocumentHandler) ListDocumentReindexBatches(ctx context.Context, req contract.ListDocumentReindexBatchesRequestObject) (contract.ListDocumentReindexBatchesResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	input, e := pageInput(req.Params.Limit, req.Params.Cursor)
	input.ActiveOnly = req.Params.ActiveOnly != nil && *req.Params.ActiveOnly
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	v, e := handler.ingestion.Batches(ctx, a, false, input)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	out := contract.DocumentReindexBatchPage{Counts: &contract.JobStatusCounts{Groups: []contract.JobStatusCount{}}, Items: []contract.DocumentReindexBatch{}, NextCursor: documentOptionalStringMapper(v.NextCursor)}
	for _, count := range v.Counts {
		out.Counts.Groups = append(out.Counts.Groups, contract.JobStatusCount{Status: count.Status, Count: count.Count})
	}
	for _, item := range v.Items {
		out.Items = append(out.Items, documentReindexBatchResponseMapper(item))
	}
	return contract.ListDocumentReindexBatches200JSONResponse(out), nil
}
func (handler *DocumentHandler) GetDocumentReindexBatch(ctx context.Context, req contract.GetDocumentReindexBatchRequestObject) (contract.GetDocumentReindexBatchResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	v, e := handler.ingestion.Batch(ctx, a, false, req.BatchId.String())
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.GetDocumentReindexBatch200JSONResponse(documentReindexBatchResponseMapper(v)), nil
}
func (handler *DocumentHandler) CreateDocumentReindexBatch(ctx context.Context, req contract.CreateDocumentReindexBatchRequestObject) (contract.CreateDocumentReindexBatchResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	if req.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "reindex request is required"), nil
	}
	v, e := handler.ingestion.CreateBatch(ctx, a, false, domain.DocumentReindexRequest{RequestID: req.Body.RequestId.String(), ConfigurationRevision: req.Body.ConfigurationRevision})
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.CreateDocumentReindexBatch202JSONResponse(documentReindexBatchResponseMapper(v)), nil
}

func (handler *DocumentHandler) ListSystemDocumentReindexBatches(ctx context.Context, req contract.ListSystemDocumentReindexBatchesRequestObject) (contract.ListSystemDocumentReindexBatchesResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	input, e := pageInput(req.Params.Limit, req.Params.Cursor)
	input.ActiveOnly = req.Params.ActiveOnly != nil && *req.Params.ActiveOnly
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	v, e := handler.ingestion.Batches(ctx, a, true, input)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	out := contract.DocumentReindexBatchPage{Counts: &contract.JobStatusCounts{Groups: []contract.JobStatusCount{}}, Items: []contract.DocumentReindexBatch{}, NextCursor: documentOptionalStringMapper(v.NextCursor)}
	for _, count := range v.Counts {
		out.Counts.Groups = append(out.Counts.Groups, contract.JobStatusCount{Status: count.Status, Count: count.Count})
	}
	for _, item := range v.Items {
		out.Items = append(out.Items, documentReindexBatchResponseMapper(item))
	}
	return contract.ListSystemDocumentReindexBatches200JSONResponse(out), nil
}
func (handler *DocumentHandler) GetSystemDocumentReindexBatch(ctx context.Context, req contract.GetSystemDocumentReindexBatchRequestObject) (contract.GetSystemDocumentReindexBatchResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	v, e := handler.ingestion.Batch(ctx, a, true, req.BatchId.String())
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.GetSystemDocumentReindexBatch200JSONResponse(documentReindexBatchResponseMapper(v)), nil
}
func (handler *DocumentHandler) CreateSystemDocumentReindexBatch(ctx context.Context, req contract.CreateSystemDocumentReindexBatchRequestObject) (contract.CreateSystemDocumentReindexBatchResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	if req.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "reindex request is required"), nil
	}
	v, e := handler.ingestion.CreateBatch(ctx, a, true, domain.DocumentReindexRequest{RequestID: req.Body.RequestId.String(), ConfigurationRevision: req.Body.ConfigurationRevision})
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.CreateSystemDocumentReindexBatch202JSONResponse(documentReindexBatchResponseMapper(v)), nil
}

func (handler *DocumentHandler) RetryDocumentAI(ctx context.Context, req contract.RetryDocumentAIRequestObject) (contract.RetryDocumentAIResponseObject, error) {
	a, e := actor(ctx)
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	if req.Body == nil {
		return models.NewDocumentErrorResponse(400, "invalid_request", "AI retry request is required"), nil
	}
	v, e := handler.ingestion.RetryAI(ctx, a, req.Id.String(), domain.DocumentReindexRequest{RequestID: req.Body.RequestId.String(), ConfigurationRevision: req.Body.ConfigurationRevision})
	if e != nil {
		return handler.failure(ctx, e), nil
	}
	return contract.RetryDocumentAI202JSONResponse(documentAIResponseMapper(v)), nil
}
