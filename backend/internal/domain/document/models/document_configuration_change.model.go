package models

type DocumentLLMCredentialWrite struct {
	ID, Key string
}

type DocumentConfigurationChange struct {
	ExpectedRevision      int64
	Configuration         DocumentProcessingConfiguration
	Credential            *DocumentLLMCredentialWrite
	Reindex, RescheduleAI bool
}
