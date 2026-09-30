package models

type ChatContextQuery struct {
	MessageLimit    int
	AssistantStatus string
}

func ChatContextSelection() ChatContextQuery {
	return ChatContextQuery{MessageLimit: ChatHistoryMessages, AssistantStatus: "completed"}
}
