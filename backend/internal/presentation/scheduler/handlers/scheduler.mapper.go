package handlers

import (
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

func schedulerSettingsResponseMapper(settings m.SchedulerSettings) contract.WorkloadSettings {
	response := contract.WorkloadSettings{Revision: settings.Revision, OllamaQueueSize: settings.OllamaQueueSize, Resources: make([]contract.WorkloadResource, 0, len(settings.Resources)), Pipelines: make([]contract.WorkloadPipeline, 0, len(settings.Pipelines))}
	for _, resource := range settings.Resources {
		response.Resources = append(response.Resources, contract.WorkloadResource{Id: resource.ID, Label: resource.Label, Limit: resource.Limit, MaximumLimit: resource.MaximumLimit, ActiveJobs: resource.ActiveJobs})
	}
	for _, pipeline := range settings.Pipelines {
		response.Pipelines = append(response.Pipelines, contract.WorkloadPipeline{Id: pipeline.ID, Label: pipeline.Label, ResourceIds: append([]string{}, pipeline.ResourceIDs...)})
	}
	return response
}
