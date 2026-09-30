package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

func schedulerSettingsMapper(record r.SchedulerSettingsRecord) m.SchedulerSettings {
	settings := m.SchedulerSettings{Revision: record.Revision, OllamaQueueSize: record.OllamaQueueSize, Resources: make([]m.SchedulerResource, 0, len(record.Resources)), Pipelines: make([]m.SchedulerPipeline, 0, len(record.Pipelines))}
	for _, resource := range record.Resources {
		settings.Resources = append(settings.Resources, m.SchedulerResource{ID: resource.ID, Label: resource.Label, Limit: resource.Limit, MaximumLimit: resource.MaximumLimit, ActiveJobs: resource.ActiveJobs})
	}
	for _, pipeline := range record.Pipelines {
		settings.Pipelines = append(settings.Pipelines, m.SchedulerPipeline{ID: pipeline.ID, Label: pipeline.Label, ResourceIDs: append([]string{}, pipeline.ResourceIDs...)})
	}
	return settings
}
