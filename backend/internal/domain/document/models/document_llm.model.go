package models

type DocumentLLMConfiguration struct {
	PropertyThinkingEnabled                bool `json:",omitempty"`
	InvoiceThinkingEnabled                 bool `json:",omitempty"`
	LMStudioCompatibility                  bool `json:",omitempty"`
	Enabled                                bool
	InvoiceEnabled                         *bool
	ContextLength                          int
	Provider, Model, BaseURL, CredentialID string
}

type DocumentLLMConfigurationUpdate struct {
	PropertyThinkingEnabled  *bool
	InvoiceThinkingEnabled   *bool
	LMStudioCompatibility    *bool
	Enabled                  bool
	InvoiceEnabled           *bool
	ContextLength            *int
	Provider, Model, BaseURL string
	APIKey                   *string
	ClearAPIKey              bool
}

type DocumentModelContext struct {
	Model            string
	MaxContextLength int
}

type DocumentPropertyWork struct {
	Eligible                   bool
	Job                        DocumentJob
	Configuration              DocumentLLMConfiguration
	Stage, Text                string
	Revision, MetadataRevision int64
	Metadata                   DocumentMetadata
	NextStage                  string
}
