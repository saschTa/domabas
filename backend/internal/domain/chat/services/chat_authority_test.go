package services

import (
	"context"
	"errors"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	i "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"testing"
)

type chatAllowAuthority struct{}

func (chatAllowAuthority) ResolveAuthority(_ context.Context, a i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	a.Permissions = []i.IdentityPermission{"chat:use", "system:chat:manage", "documents:read", "documents:search", "documents:ocr:read"}
	return a, nil
}
func (s chatAllowAuthority) ResolveBackgroundAuthority(ctx context.Context, account, user string, revision int64) (i.IdentityPrincipal, error) {
	return s.ResolveAuthority(ctx, i.IdentityPrincipal{AccountID: account, UserID: user, CredentialRevision: revision})
}
func (f *chatExecutionFixture) ExecutionAuthority(context.Context, string, m.ChatContextQuery) (m.ChatExecutionAuthority, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return m.ChatExecutionAuthority{Actor: f.work.Actor}, nil
}

type chatDeniedAuthority struct{ chatAllowAuthority }

func (chatDeniedAuthority) ResolveAuthority(context.Context, i.IdentityPrincipal) (i.IdentityPrincipal, error) {
	return i.IdentityPrincipal{}, i.ErrUnauthorized
}
func (chatDeniedAuthority) ResolveBackgroundAuthority(context.Context, string, string, int64) (i.IdentityPrincipal, error) {
	return i.IdentityPrincipal{}, i.ErrForbidden
}

func TestChatServiceChecksEveryForegroundEntryPoint(t *testing.T) {
	s := NewChatService(nil, nil, nil, chatDeniedAuthority{})
	a := m.ChatActor{}
	checks := []func() error{
		func() error { _, err := s.Configuration(t.Context(), a, false); return err },
		func() error { _, err := s.Configuration(t.Context(), a, true); return err },
		func() error { _, err := s.UpdateConfiguration(t.Context(), a, m.ChatConfigurationUpdate{}); return err },
		func() error { _, err := s.Conversations(t.Context(), a, m.ChatPageRequest{}); return err },
		func() error { _, err := s.CreateConversation(t.Context(), a, "request"); return err },
		func() error { _, err := s.Conversation(t.Context(), a, "id"); return err },
		func() error { return s.DeleteConversation(t.Context(), a, "id") },
		func() error { _, err := s.Messages(t.Context(), a, "id", m.ChatPageRequest{}); return err },
		func() error { _, err := s.Send(t.Context(), a, "id", m.ChatSendInput{}); return err },
		func() error { _, err := s.Cancel(t.Context(), a, "id", "turn"); return err },
		func() error { _, err := s.Models(t.Context(), a, 10, 0); return err },
		func() error { _, err := s.ModelContext(t.Context(), a, "model"); return err },
	}
	for index, check := range checks {
		if err := check(); !errors.Is(err, m.ErrUnauthorized) {
			t.Fatalf("entry point %d: %v", index, err)
		}
	}
}
func TestChatBackgroundDenialPreventsWorkAndPublication(t *testing.T) {
	repo := &chatExecutionFixture{work: chatFixtureWork()}
	s := NewChatExecutionService(repo, nil, chatDeniedAuthority{})
	if _, err := s.Work(t.Context(), "id", "token"); !errors.Is(err, m.ErrForbidden) {
		t.Fatal(err)
	}
	if err := s.Complete(t.Context(), "id", "token", "secret"); !errors.Is(err, m.ErrForbidden) || repo.complete != "" {
		t.Fatal(err, repo.complete)
	}
}
