package models

type SchedulerRetainedSnapshot struct {
	LLM struct {
		Enabled           bool
		InvoiceEnabled    *bool
		Provider, BaseURL string
	}
}

type SchedulerRetainedExecution struct {
	WorkflowID, Pipeline, Provider, BaseURL string
	Configuration                           []byte
	Combined                                bool
}
