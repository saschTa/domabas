package handlers

import (
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/google/uuid"
)

func paperlessSettingsResponseMapper(settings m.PaperlessSettings) contract.PaperlessSettings {
	return contract.PaperlessSettings{RetrievalConcurrency: settings.RetrievalConcurrency, Revision: settings.Revision, MinimumRetrievalConcurrency: m.MinRetrievalConcurrency, MaximumRetrievalConcurrency: m.MaxRetrievalConcurrency}
}

func paperlessOptionalStringMapper(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func paperlessOutcomesResponseMapper(values []m.PaperlessOutcome) []contract.PaperlessOutcome {
	outcomes := []contract.PaperlessOutcome{}
	for _, o := range values {
		var id *uuid.UUID
		if o.DocumentID != "" {
			parsed, err := uuid.Parse(o.DocumentID)
			if err == nil {
				id = &parsed
			}
		}
		outcomes = append(outcomes, contract.PaperlessOutcome{SourceId: o.SourceID, Title: o.Title, Status: contract.PaperlessOutcomeStatus(o.Status), FailureCode: paperlessOptionalStringMapper(o.FailureCode), DocumentId: id})
	}
	return outcomes
}

func paperlessRunResponseMapper(v m.PaperlessRun) contract.PaperlessRun {
	return contract.PaperlessRun{Id: uuid.MustParse(v.ID), ServerUrl: v.ServerURL, State: contract.PaperlessRunState(v.State), Stage: contract.PaperlessRunStage(v.Stage), FailureCode: paperlessOptionalStringMapper(v.FailureCode), Discovered: v.Discovered, Imported: v.Imported, Duplicates: v.Duplicates, Failed: v.Failed, CancelRequested: v.CancelRequested, CreatedAt: v.CreatedAt, UpdatedAt: v.UpdatedAt, Outcomes: paperlessOutcomesResponseMapper(v.Outcomes)}
}

func paperlessPageRequestMapper(limit *int, cursor *string) m.PaperlessPageRequest {
	result := m.PaperlessPageRequest{Limit: 20}
	if limit != nil {
		result.Limit = *limit
	}
	if cursor != nil {
		result.Cursor = *cursor
	}
	return result
}

func paperlessJobCountsResponseMapper(counts []m.PaperlessJobStatusCount) *contract.JobStatusCounts {
	out := make([]contract.JobStatusCount, 0, len(counts))
	for _, count := range counts {
		out = append(out, contract.JobStatusCount{Status: count.Status, Count: count.Count})
	}
	return &contract.JobStatusCounts{Groups: out}
}
