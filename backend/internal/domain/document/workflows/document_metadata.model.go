package workflows

import (
	"time"
)

type DocumentMetadataResult struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
}

type DocumentMetadataRequest struct {
	AccountID  string `json:"accountId"`
	DocumentID string `json:"documentId"`
}
