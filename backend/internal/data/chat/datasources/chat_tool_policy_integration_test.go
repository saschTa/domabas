//go:build integration

package datasources

import (
	"errors"
	"strings"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
)

func TestChatToolGuardsPersistFeedbackAndRecoverStoppingState(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	turn := f.send(conversation.ID, "Find contracts").AssistantMessage.TurnID
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, turn, token); err != nil {
		t.Fatal(err)
	}
	document := uuid.NewString()
	f.exec("INSERT INTO documents(id,account_id,title,description,ocr_machine_text,created_at) VALUES($1,$2,'Contract example','',$3,clock_timestamp())", document, f.actor.AccountID, strings.Repeat("e", 8001))
	steps := []struct {
		action  m.ChatAction
		outcome string
	}{
		{m.ChatAction{Kind: "read_document", DocumentID: document}, "unknown_document"},
		{m.ChatAction{Kind: "search_documents", Query: "Contract"}, "progress"},
		{m.ChatAction{Kind: "read_document", DocumentID: document}, "progress"},
		{m.ChatAction{Kind: "read_document", DocumentID: document, Offset: 8000}, "progress"},
		{m.ChatAction{Kind: "search_documents", Query: "example"}, "no_new_evidence"},
		{m.ChatAction{Kind: "search_documents", Query: "  CONTRACT  ", ToolCallID: "different-id"}, "repeated_call"},
		{m.ChatAction{Kind: "read_document", DocumentID: document, Offset: 16000}, "invalid_offset"},
	}
	for ordinal, step := range steps {
		result, err := f.source.Tool(ctx, turn, token, ordinal, step.action)
		if err != nil || result.Outcome != step.outcome {
			t.Fatalf("step %d: %+v, %v", ordinal, result, err)
		}
		if !result.Executed() && (len(result.Sources) != 0 || !strings.Contains(result.Content, step.outcome)) {
			t.Fatal("rejection omitted feedback or manufactured evidence", result)
		}
		replay, err := f.source.Tool(ctx, turn, token, ordinal, step.action)
		if err != nil || replay.Content != result.Content || replay.Outcome != result.Outcome || len(replay.Sources) != len(result.Sources) {
			t.Fatal("replay changed evidence or progress", replay, err)
		}
	}
	if err := f.source.Release(ctx, turn, token); err != nil {
		t.Fatal(err)
	}
	token = uuid.NewString()
	if err := f.source.Acquire(ctx, turn, token); err != nil {
		t.Fatal(err)
	}
	work, err := f.source.Work(ctx, turn, token)
	if err != nil || !m.ChatToolsMustAnswer(work.Tools) || len(work.Tools) != len(steps) || work.Tools[2].NextOffset == nil || *work.Tools[2].NextOffset != 8000 {
		t.Fatal("recovery lost stopping state or continuation", work.Tools, err)
	}
	_, err = f.source.Tool(ctx, turn, token, len(steps), m.ChatAction{Kind: "search_documents", Query: "another"})
	var failure m.ChatProcessingError
	if !errors.As(err, &failure) || failure.Code != "tool_limit" {
		t.Fatal("adapter allowed execution after no-progress stop", err)
	}
}

func TestChatToolGuardRejectsUnreturnedPaginationAndErrorQueries(t *testing.T) {
	for _, test := range []struct {
		name    string
		action  m.ChatAction
		outcome string
	}{
		{"error query", m.ChatAction{Kind: "search_documents", Query: "document_unavailable"}, "error_query"},
		{"search offset", m.ChatAction{Kind: "search_documents", Query: "empty", Offset: 1}, "invalid_offset"},
		{"catalog offset", m.ChatAction{Kind: "list_tools", Offset: 2}, "invalid_offset"},
	} {
		t.Run(test.name, func(t *testing.T) {
			f := newChatFixture(t)
			turn := f.send(f.conversation().ID, "Find a document").AssistantMessage.TurnID
			if _, err := f.source.Dispatch(t.Context()); err != nil {
				t.Fatal(err)
			}
			token := uuid.NewString()
			if err := f.source.Acquire(t.Context(), turn, token); err != nil {
				t.Fatal(err)
			}
			result, err := f.source.Tool(t.Context(), turn, token, 0, test.action)
			if err != nil || result.Outcome != test.outcome || result.Executed() || len(result.Sources) != 0 || result.NextOffset != nil {
				t.Fatal("invalid proposal executed", result, err)
			}
		})
	}
}
