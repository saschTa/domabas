package models

import (
	"errors"
	"strings"
	"testing"
)

func TestChatConfigurationCredentialRetentionAndOptionalContext(t *testing.T) {
	current := ChatConfiguration{Revision: 3, Provider: "openai", BaseURL: "https://one.test", CredentialID: "old", ContextLength: 32768}
	for _, test := range []struct {
		name    string
		update  ChatConfigurationUpdate
		key     string
		context int
	}{
		{"same provider", ChatConfigurationUpdate{ExpectedRevision: 3, Provider: "openai", BaseURL: "https://one.test"}, "old", 32768},
		{"provider changed", ChatConfigurationUpdate{ExpectedRevision: 3, Provider: "ollama"}, "", 32768},
		{"endpoint changed", ChatConfigurationUpdate{ExpectedRevision: 3, Provider: "openai", BaseURL: "https://two.test"}, "", 32768},
		{"clear", ChatConfigurationUpdate{ExpectedRevision: 3, Provider: "openai", BaseURL: "https://one.test", ClearAPIKey: true}, "", 32768},
		{"context", ChatConfigurationUpdate{ExpectedRevision: 3, Provider: "openai", BaseURL: "https://one.test", ContextLength: new(65536)}, "old", 65536},
	} {
		t.Run(test.name, func(t *testing.T) {
			plan, err := PlanChatConfiguration(current, test.update, false)
			if err != nil || plan.Configuration.CredentialID != test.key || plan.Configuration.ContextLength != test.context {
				t.Fatal(plan, err)
			}
		})
	}
	if _, err := PlanChatConfiguration(current, ChatConfigurationUpdate{ExpectedRevision: 2}, false); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
}

func TestChatSendPlanSelectsLimitsAndUnicodeTitle(t *testing.T) {
	facts := ChatSendFacts{Configuration: ChatConfiguration{Revision: 4, Enabled: true}}
	command, err := PlanChatSend(facts, ChatSendInput{Content: " \n" + strings.Repeat("ä", 81) + " "})
	if err != nil || len([]rune(command.InitialTitle)) != 80 || command.GlobalLimit != 200 || command.OwnerLimit != 10 || command.ExpectedConfigurationRevision != 4 {
		t.Fatal(command, err)
	}
	facts.Conversation.ActiveTurnID = "active"
	if _, err := PlanChatSend(facts, ChatSendInput{}); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	facts.Conversation.ActiveTurnID = ""
	facts.Configuration.Enabled = false
	if _, err := PlanChatSend(facts, ChatSendInput{}); !errors.Is(err, ErrDisabled) {
		t.Fatal(err)
	}
}

func TestChatThinkingOmissionAndExplicitFalse(t *testing.T) {
	current := ChatConfiguration{Revision: 1, Provider: "ollama"}
	for _, step := range []struct {
		value *bool
		want  bool
	}{{new(true), true}, {nil, true}, {new(false), false}, {nil, false}} {
		plan, err := PlanChatConfiguration(current, ChatConfigurationUpdate{ExpectedRevision: 1, Provider: "ollama", ThinkingEnabled: step.value}, true)
		if err != nil || plan.Configuration.ThinkingEnabled != step.want {
			t.Fatal("thinking update lost", plan, err)
		}
		current = plan.Configuration
	}
}
