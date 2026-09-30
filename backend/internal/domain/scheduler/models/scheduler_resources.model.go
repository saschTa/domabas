package models

type SchedulerProviderResource struct{ ID, Origin string }

type SchedulerRetainedConfiguration struct {
	Pipeline, Provider, BaseURL        string
	Combined, SnapshotPresent          bool
	PropertiesEnabled, InvoicesEnabled bool
	LLMProvider, LLMBaseURL            string
}
