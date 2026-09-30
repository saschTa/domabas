package models

type SchedulerSettingsPlan struct {
	ExpectedRevision  int64
	ExpectedQueueSize int
	ExpectedResources []SchedulerResource
	Materialize       []SchedulerResource
	Changes           []SchedulerResourceUpdate
}
