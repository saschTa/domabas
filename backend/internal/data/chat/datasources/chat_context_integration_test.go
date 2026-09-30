//go:build integration

package datasources

import (
	"errors"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
)

func TestChatContextSettingsOmissionAndAcceptedSnapshot(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	configuration, err := f.source.Configuration(ctx, f.actor, true)
	if err != nil || configuration.ContextLength != 32768 {
		t.Fatal("unexpected default", configuration, err)
	}
	requested := 65536
	update := m.ChatConfigurationUpdate{ExpectedRevision: configuration.Revision, Enabled: true, Provider: "ollama", Model: configuration.Model, ContextLength: &requested}
	configuration, err = f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || configuration.ContextLength != requested || configuration.Revision != update.ExpectedRevision+1 {
		t.Fatal(configuration, err)
	}
	update.ExpectedRevision = configuration.Revision
	update.ContextLength = nil
	unchanged, err := f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || unchanged.ContextLength != requested || unchanged.Revision != configuration.Revision {
		t.Fatal("omitted value changed saved context", unchanged, err)
	}
	conversation := f.conversation()
	sent := f.send(conversation.ID, "Keep my accepted context")
	requested = 8192
	update.ContextLength = &requested
	changed, err := f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || changed.ContextLength != requested {
		t.Fatal(changed, err)
	}
	if _, err := f.source.UpdateConfiguration(ctx, f.actor, update); !errors.Is(err, m.ErrConflict) {
		t.Fatal("stale context write accepted", err)
	}
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal(err)
	}
	work, err := f.source.Work(ctx, sent.AssistantMessage.TurnID, token)
	if err != nil || work.Configuration.ContextLength != 65536 || work.Configuration.Revision != configuration.Revision {
		t.Fatal("accepted turn context changed", work.Configuration, err)
	}
	update.ExpectedRevision = changed.Revision
	update.ContextLength = nil
	update.Provider, update.BaseURL = "openai", "https://external.test/v1"
	external, err := f.source.UpdateConfiguration(ctx, f.actor, update)
	if err != nil || external.ContextLength != 8192 {
		t.Fatal("provider switch lost context", external, err)
	}
}
