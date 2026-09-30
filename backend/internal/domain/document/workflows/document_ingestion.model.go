package workflows

type DocumentIngestionRequest struct {
	AIAttempt          int64  `json:"aiAttempt,omitempty"`
	UnlimitedInference bool   `json:"unlimitedInference,omitempty"`
	AccountID          string `json:"accountId"`
	DocumentID         string `json:"documentId"`
	Generation         int64  `json:"generation"`
}

type DocumentIngestionFailure struct {
	Job  DocumentIngestionRequest `json:"job"`
	Code string                   `json:"code"`
}

type DocumentIngestionResult struct {
	State string `json:"state"`
}
