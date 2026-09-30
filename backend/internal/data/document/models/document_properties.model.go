package models

type DocumentExtractedProperties struct {
	Description  string   `json:"description"`
	Tags         []string `json:"tags"`
	Sender       string   `json:"sender"`
	Recipients   []string `json:"recipients"`
	DocumentDate string   `json:"documentDate"`
	Subject      string   `json:"subject"`
}
