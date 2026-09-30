package provider

import m "github.com/domabas/domabas/backend/internal/domain/chat/models"

func providerTranscriptMapper(messages []m.ChatProviderMessage) []ChatProviderMessage {
	result := make([]ChatProviderMessage, 0, len(messages))
	for _, message := range messages {
		mapped := ChatProviderMessage{Role: message.Role, Content: message.Content, ToolCallID: message.ToolCallID}
		if message.ToolCall != nil {
			mapped.ToolCalls = []ChatProviderToolCall{{ID: message.ToolCall.ID, Type: "function", Function: ChatProviderToolFunction{Name: message.ToolCall.Name, Arguments: message.ToolCall.Arguments}}}
		}
		result = append(result, mapped)
	}
	return result
}
