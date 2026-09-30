package models

import (
	"strings"
	"testing"
)

func TestChatInputBoundsAndProviderSecretValidation(t *testing.T) {
	valid := ChatSendInput{RequestID: "12345678-1234-4234-8234-123456789012", Content: strings.Repeat("ü", 8000)}
	if err := valid.Validate(); err != nil {
		t.Fatal(err)
	}
	valid.Content += "x"
	if err := valid.Validate(); err == nil {
		t.Fatal("oversized unicode accepted")
	}
	valid.Content = "\x00"
	if err := valid.Validate(); err == nil {
		t.Fatal("nul accepted")
	}
	for _, url := range []string{"https://user:secret@example.test/v1", "https://example.test/v1?token=secret", "file:///tmp/model", "https://example.test/v1#fragment"} {
		if _, err := (ChatConfigurationUpdate{ExpectedRevision: 1, Provider: "openai", Model: "model", BaseURL: url}).Normalize(); err == nil {
			t.Fatalf("bad endpoint accepted: %q", url)
		}
	}
	key := "secret"
	if _, err := (ChatConfigurationUpdate{ExpectedRevision: 1, Provider: "openai", Model: "model", BaseURL: "http://private.test/v1", APIKey: &key, ClearAPIKey: true}).Normalize(); err == nil {
		t.Fatal("conflicting secret update accepted")
	}
	if _, err := (ChatConfigurationUpdate{ExpectedRevision: 1, Provider: "ollama", Model: "qwen3.5:4b", APIKey: &key}).Normalize(); err == nil {
		t.Fatal("internal secret accepted")
	}
}
func TestChatToolActionsRejectUnboundedOrArbitraryArguments(t *testing.T) {
	for _, action := range []ChatAction{{Kind: "shell", Content: "ls"}, {Kind: "answer"}, {Kind: "search_documents", Query: "x", Offset: 10001}, {Kind: "read_document", DocumentID: "https://foreign.test"}, {Kind: "read_document", DocumentID: "12345678-1234-4234-8234-123456789012", Offset: -1}} {
		if action.Validate() == nil {
			t.Fatal("bad tool accepted", action)
		}
	}
}
func TestChatContextLengthValidationPreservesOmission(t *testing.T) {
	update := ChatConfigurationUpdate{ExpectedRevision: 1, Provider: "ollama", Model: "qwen3.5:4b"}
	if normalized, err := update.Normalize(); err != nil || normalized.ContextLength != nil {
		t.Fatal("omitted context changed", normalized, err)
	}
	for _, value := range []int{-1, 0, 1023, 1048577} {
		update.ContextLength = &value
		if _, err := update.Normalize(); err == nil {
			t.Fatal("invalid context accepted", value)
		}
	}
	for _, value := range []int{1024, 32768, 1048576} {
		update.ContextLength = &value
		if normalized, err := update.Normalize(); err != nil || *normalized.ContextLength != value {
			t.Fatal("valid context changed", normalized, err)
		}
	}
}
