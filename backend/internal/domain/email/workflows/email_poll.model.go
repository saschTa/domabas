package workflows

type EmailPollWorkflowInput struct {
	RunID string `json:"runId"`
}

type EmailPollPageInput struct {
	RunID     string `json:"runId"`
	PageIndex int    `json:"pageIndex"`
}

type EmailPollWorkflowResult struct {
	HasMore bool `json:"hasMore"`
}
