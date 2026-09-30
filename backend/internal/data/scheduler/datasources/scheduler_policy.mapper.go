package datasources

import (
	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

func schedulerResourceRecordsMapper(values []m.SchedulerResource) []r.SchedulerResourceRecord {
	result := make([]r.SchedulerResourceRecord, len(values))
	for i, v := range values {
		result[i] = r.SchedulerResourceRecord{ID: v.ID, Label: v.Label, Limit: v.Limit, MaximumLimit: v.MaximumLimit, ActiveJobs: v.ActiveJobs}
	}
	return result
}

func schedulerPipelineRecordsMapper(values []m.SchedulerPipeline) []r.SchedulerPipelineRecord {
	result := make([]r.SchedulerPipelineRecord, len(values))
	for i, v := range values {
		result[i] = r.SchedulerPipelineRecord{ID: v.ID, Label: v.Label, ResourceIDs: v.ResourceIDs}
	}
	return result
}
