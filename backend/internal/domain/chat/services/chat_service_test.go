package services

import (
	"context"
	"errors"
	"testing"

	p "github.com/domabas/domabas/backend/internal/domain/chat/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

type chatModelContextRepositoryFixture struct {
	p.ChatRepository
	authorize func(m.ChatActor, bool) error
}

func (r chatModelContextRepositoryFixture) Configuration(_ context.Context, actor m.ChatActor, admin bool) (m.ChatConfiguration, error) {
	return m.ChatConfiguration{}, r.authorize(actor, admin)
}

type chatModelContextProviderFixture struct {
	lookup func(string) (m.ChatModelContext, error)
}

func (p chatModelContextProviderFixture) ModelContext(_ context.Context, model string) (m.ChatModelContext, error) {
	return p.lookup(model)
}

func TestChatModelContextRequiresAdministratorBeforeProviderRead(t *testing.T) {
	actor := m.ChatActor{UserID: "actor", AccountID: "namespace"}
	for _, denied := range []bool{false, true} {
		t.Run(map[bool]string{false: "authorized", true: "forbidden"}[denied], func(t *testing.T) {
			called := false
			repository := chatModelContextRepositoryFixture{authorize: func(got m.ChatActor, admin bool) error {
				if got != actor || !admin {
					t.Fatal("lookup did not check administrator authority", got, admin)
				}
				if denied {
					return m.ErrForbidden
				}
				return nil
			}}
			provider := chatModelContextProviderFixture{lookup: func(model string) (m.ChatModelContext, error) {
				called = true
				return m.ChatModelContext{Model: model, MaxContextLength: 131072}, nil
			}}
			service := NewChatService(repository, nil, provider, chatAllowAuthority{})
			result, err := service.ModelContext(t.Context(), actor, "library/qwen3.5:4b")
			if denied {
				if called || !errors.Is(err, m.ErrForbidden) {
					t.Fatal("unauthorized provider access", called, err)
				}
			} else if err != nil || !called || result.Model != "library/qwen3.5:4b" || result.MaxContextLength != 131072 {
				t.Fatal(result, err)
			}
		})
	}
	service := NewChatService(nil, nil, nil, chatAllowAuthority{})
	for _, model := range []string{"", "bad model", "bad\nmodel"} {
		if _, err := service.ModelContext(t.Context(), actor, model); err == nil {
			t.Fatal("invalid model accepted", model)
		}
	}
}
