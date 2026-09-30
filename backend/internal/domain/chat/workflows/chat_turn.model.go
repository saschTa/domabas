package workflows

type ChatTurnRequest struct {
	TurnID    string `json:"turnId"`
	AccountID string `json:"accountId"`
}

type ChatTurnFailure struct {
	Request ChatTurnRequest `json:"request"`
	Code    string          `json:"code"`
}

type ChatTurnResult struct {
	State string `json:"state"`
}

type ChatStepRequest struct {
	Request ChatTurnRequest `json:"request"`
	Ordinal int             `json:"ordinal"`
}

type ChatStepResult struct {
	Completed bool `json:"completed"`
}
