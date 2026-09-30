package models

import "testing"

func TestChatToolPolicyUsesReturnedEvidenceAndContinuation(t *testing.T) {
	nextCatalog, nextSearch, nextRead := 2, 10, 8000
	tools := []ChatToolResult{
		{Action: ChatAction{Kind: "list_tools"}, Outcome: "progress", NextOffset: &nextCatalog},
		{Action: ChatAction{Kind: "search_documents", Query: "Contract", ToolCallID: "original"}, Outcome: "progress", NextOffset: &nextSearch, Sources: []ChatSource{{DocumentID: "found-document"}}},
		{Action: ChatAction{Kind: "read_document", DocumentID: "found-document"}, Outcome: "progress", NextOffset: &nextRead},
		{Action: ChatAction{Kind: "search_documents", Query: "missing"}, Outcome: "empty_result"},
	}
	for _, test := range []struct {
		name   string
		action ChatAction
		want   string
	}{
		{"new query", ChatAction{Kind: "search_documents", Query: "salary"}, ""},
		{"duplicate with new call ID", ChatAction{Kind: "search_documents", Query: "  CONTRACT  ", ToolCallID: "new"}, "repeated_call"},
		{"search continuation", ChatAction{Kind: "search_documents", Query: "contract", Offset: 10}, ""},
		{"other query continuation", ChatAction{Kind: "search_documents", Query: "salary", Offset: 10}, "invalid_offset"},
		{"empty search continuation", ChatAction{Kind: "search_documents", Query: "missing", Offset: 1}, "invalid_offset"},
		{"catalog continuation", ChatAction{Kind: "list_tools", Offset: 2}, ""},
		{"invented catalog offset", ChatAction{Kind: "list_tools", Offset: 1}, "invalid_offset"},
		{"read continuation", ChatAction{Kind: "read_document", DocumentID: "found-document", Offset: 8000}, ""},
		{"invented read offset", ChatAction{Kind: "read_document", DocumentID: "found-document", Offset: 1}, "invalid_offset"},
		{"duplicate read", ChatAction{Kind: "read_document", DocumentID: "found-document", ToolCallID: "new"}, "repeated_call"},
		{"invented document", ChatAction{Kind: "read_document", DocumentID: "invented"}, "unknown_document"},
		{"error text query", ChatAction{Kind: "search_documents", Query: " DOCUMENT_UNAVAILABLE "}, "error_query"},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := ChatToolRejection(test.action, tools); got != test.want {
				t.Fatalf("got %q, want %q", got, test.want)
			}
		})
	}
	if got := ChatToolRejection(ChatAction{Kind: "read_document", DocumentID: "found-document"}, tools[:2]); got != "" {
		t.Fatalf("a searched document cannot be read: %s", got)
	}
	if got := ChatToolRejection(ChatAction{Kind: "read_document", DocumentID: "found-document", Offset: 8000}, tools[2:3]); got != "unknown_document" {
		t.Fatalf("a read reply alone manufactured search provenance: %s", got)
	}
}

func TestChatNoProgressStopSurvivesRecoveryAndResetsOnEvidence(t *testing.T) {
	tools := []ChatToolResult{{Outcome: "empty_result"}, {Outcome: "unknown_document"}}
	if ChatToolsMustAnswer(tools) {
		t.Fatal("stopped before the recovery allowance")
	}
	tools = append(tools, ChatToolResult{Outcome: "repeated_call"})
	if !ChatToolsMustAnswer(tools) {
		t.Fatal("persisted no-progress outcomes did not stop the turn")
	}
	tools = append(tools, ChatToolResult{Outcome: "progress"})
	if ChatToolsMustAnswer(tools) {
		t.Fatal("new evidence did not reset the streak")
	}
	for len(tools) < ChatMaxToolCalls {
		tools = append(tools, ChatToolResult{Outcome: "progress"})
	}
	if !ChatToolsMustAnswer(tools) {
		t.Fatal("progress bypassed the total budget")
	}
}
