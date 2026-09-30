//go:build integration

package datasources

import (
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
	"testing"
)

func TestChatThinkingPersistsPerAcceptedTurn(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	c, err := f.source.Configuration(ctx, f.actor, true)
	if err != nil || c.ThinkingEnabled {
		t.Fatal("thinking must default off", err)
	}
	update := m.ChatConfigurationUpdate{ExpectedRevision: c.Revision, Enabled: true, Provider: "ollama", Model: c.Model, ThinkingEnabled: new(true)}
	saved, err := f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || !saved.ThinkingEnabled || saved.Revision != c.Revision+1 {
		t.Fatal("thinking save lost", saved, err)
	}
	update.ExpectedRevision, update.ThinkingEnabled = saved.Revision, nil
	unchanged, err := f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || !unchanged.ThinkingEnabled || unchanged.Revision != saved.Revision {
		t.Fatal("omission changed saved thinking", unchanged, err)
	}
	conversation := f.conversation()
	sent := f.send(conversation.ID, "Keep my accepted thinking choice")
	update.ThinkingEnabled = new(false)
	disabled, err := f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || disabled.ThinkingEnabled || disabled.Revision != saved.Revision+1 {
		t.Fatal("explicit false lost", disabled, err)
	}
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal(err)
	}
	work, err := f.source.Work(ctx, sent.AssistantMessage.TurnID, token)
	if err != nil || !work.Configuration.ThinkingEnabled || work.Configuration.Revision != saved.Revision {
		t.Fatal("accepted thinking changed", work.Configuration, err)
	}
}
