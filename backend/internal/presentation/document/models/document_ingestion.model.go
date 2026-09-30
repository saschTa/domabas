package models

import (
	"io"
)

type DocumentMetadataRequest struct {
	Title        *string   `json:"title"`
	Description  *string   `json:"description"`
	Kind         *string   `json:"kind"`
	Sender       *string   `json:"sender"`
	DocumentDate *string   `json:"documentDate"`
	Subject      *string   `json:"subject"`
	MessageID    *string   `json:"messageId"`
	Tags         *[]string `json:"tags"`
	Recipients   *[]string `json:"recipients"`
	CC           *[]string `json:"cc"`
	BCC          *[]string `json:"bcc"`
}

type documentUploadBodyKey struct{}
type DocumentUploadBody struct{ Reader io.Reader }
