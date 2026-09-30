package models

type ChatConfigurationPlan struct {
	ExpectedRevision int64
	Configuration    ChatConfiguration
	APIKey           *string
}

type ChatSendFacts struct {
	Conversation  ChatConversation
	Configuration ChatConfiguration
	Replay        *ChatSendResult
}

type ChatSendCommand struct {
	Input                         ChatSendInput
	ExpectedConfigurationRevision int64
	InitialTitle                  string
	GlobalLimit, OwnerLimit       int
}

type ChatToolEvidence struct {
	Content          string
	Sources          []ChatSource
	NextOffset       *int
	Available, Empty bool
}
