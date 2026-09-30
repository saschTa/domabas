package models

type SchedulerResourceRecord struct {
	ID, Label                       string
	Limit, MaximumLimit, ActiveJobs int
}

type SchedulerPipelineRecord struct {
	ID, Label   string
	ResourceIDs []string
}

type SchedulerSettingsRecord struct {
	Revision        int64
	OllamaQueueSize int
	Resources       []SchedulerResourceRecord
	Pipelines       []SchedulerPipelineRecord
}
