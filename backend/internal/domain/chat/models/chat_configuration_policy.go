package models

import "strings"

const (
	ChatGlobalPendingLimit = 200
	ChatOwnerPendingLimit  = 10
	ChatHistoryMessages    = 20
)

func ChatInitialTitle(content string) string {
	title := []rune(strings.Join(strings.Fields(content), " "))
	return string(title[:min(len(title), 80)])
}

func PlanChatConfiguration(current ChatConfiguration, update ChatConfigurationUpdate, internal bool) (ChatConfigurationPlan, error) {
	if current.Revision != update.ExpectedRevision {
		return ChatConfigurationPlan{}, ErrConflict
	}
	next := current
	next.Enabled, next.Provider, next.Model, next.BaseURL, next.InternalRuntime = update.Enabled, update.Provider, update.Model, update.BaseURL, internal
	if update.ContextLength != nil {
		next.ContextLength = *update.ContextLength
	}
	if update.ThinkingEnabled != nil {
		next.ThinkingEnabled = *update.ThinkingEnabled
	}
	if update.ClearAPIKey || update.Provider != current.Provider || update.BaseURL != current.BaseURL {
		next.CredentialID = ""
	}
	return ChatConfigurationPlan{ExpectedRevision: current.Revision, Configuration: next, APIKey: update.APIKey}, nil
}

func PlanChatSend(facts ChatSendFacts, input ChatSendInput) (ChatSendCommand, error) {
	if facts.Conversation.ActiveTurnID != "" {
		return ChatSendCommand{}, ErrConflict
	}
	if !facts.Configuration.Enabled {
		return ChatSendCommand{}, ErrDisabled
	}
	return ChatSendCommand{Input: input, ExpectedConfigurationRevision: facts.Configuration.Revision, InitialTitle: ChatInitialTitle(input.Content), GlobalLimit: ChatGlobalPendingLimit, OwnerLimit: ChatOwnerPendingLimit}, nil
}
