//go:build integration

package datasources

import (
	"context"
	"errors"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/google/uuid"
)

func TestChatReadsAndWritesDoNotLockAuthority(t *testing.T) {
	f := newChatFixture(t)
	conversation := f.conversation()
	for _, mode := range []string{"FOR UPDATE", "FOR NO KEY UPDATE"} {
		t.Run(mode, func(t *testing.T) {
			blocker, err := f.db.Begin(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			defer blocker.Rollback(context.Background())
			for _, query := range []struct {
				sql  string
				args []any
			}{
				{"SELECT id FROM accounts WHERE id=$1 " + mode, []any{f.actor.AccountID}},
				{"SELECT id FROM users WHERE id=$1 " + mode, []any{f.actor.UserID}},
				{"SELECT user_id FROM memberships WHERE account_id=$1 AND user_id=$2 " + mode, []any{f.actor.AccountID, f.actor.UserID}},
				{"SELECT digest FROM sessions WHERE digest=$1 " + mode, []any{f.actor.SessionDigest}},
			} {
				if _, err := blocker.Exec(t.Context(), query.sql, query.args...); err != nil {
					t.Fatal(err)
				}
			}
			ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
			defer cancel()
			if mode == "FOR NO KEY UPDATE" {
				if _, err := f.source.CreateConversation(ctx, f.actor, uuid.NewString()); err != nil {
					t.Fatalf("conversation create waited for authority locks: %v", err)
				}
				if _, err := f.source.Send(ctx, f.actor, conversation.ID, m.ChatSendInput{RequestID: uuid.NewString(), Content: "Independent send"}); err != nil {
					t.Fatalf("send waited for authority locks: %v", err)
				}
				return
			}
			for _, query := range []string{"SELECT id FROM chat_conversations FOR UPDATE", "SELECT singleton FROM chat_configuration FOR UPDATE", "SELECT singleton FROM chat_admission FOR UPDATE"} {
				if _, err := blocker.Exec(t.Context(), query); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := f.source.Configuration(ctx, f.actor, true); err != nil {
				t.Fatalf("configuration read waited for locks: %v", err)
			}
			if _, err := f.source.Conversation(ctx, f.actor, conversation.ID); err != nil {
				t.Fatal(err)
			}
			if _, err := f.source.Conversations(ctx, f.actor, m.ChatPageRequest{Limit: 20}); err != nil {
				t.Fatal(err)
			}
			if _, err := f.source.Messages(ctx, f.actor, conversation.ID, m.ChatPageRequest{Limit: 20}); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestChatAcceptanceRetainsCredentialDuringRotation(t *testing.T) {
	f := newChatFixture(t)
	oldKey := "old-provider-key"
	config, err := f.source.UpdateConfiguration(t.Context(), f.actor, m.ChatConfigurationUpdate{ExpectedRevision: 1, Enabled: true, Provider: "openai", Model: "test-model", BaseURL: "https://provider.example.test", APIKey: &oldKey})
	if err != nil {
		t.Fatal(err)
	}
	conversation := f.conversation()
	blocker, err := f.db.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback(context.Background())
	if _, err := blocker.Exec(t.Context(), "SELECT singleton FROM chat_admission FOR UPDATE"); err != nil {
		t.Fatal(err)
	}
	var pid int
	if err := blocker.QueryRow(t.Context(), "SELECT pg_backend_pid()").Scan(&pid); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	sent := make(chan error, 1)
	go func() {
		_, err := f.source.Send(ctx, f.actor, conversation.ID, m.ChatSendInput{RequestID: uuid.NewString(), Content: "Keep accepted credentials"})
		sent <- err
	}()
	waiters := func(count int) {
		t.Helper()
		ticker := time.NewTicker(5 * time.Millisecond)
		defer ticker.Stop()
		for {
			var waiting int
			if err := f.database.Database().QueryRow(ctx, `WITH RECURSIVE waiting(pid) AS (SELECT pid FROM pg_stat_activity WHERE $1=ANY(pg_blocking_pids(pid)) UNION SELECT a.pid FROM pg_stat_activity a JOIN waiting w ON w.pid=ANY(pg_blocking_pids(a.pid))) SELECT count(*) FROM waiting`, pid).Scan(&waiting); err != nil {
				t.Fatal(err)
			}
			if waiting >= count {
				return
			}
			select {
			case <-ctx.Done():
				t.Fatal("operations did not reach credential fence")
			case <-ticker.C:
			}
		}
	}
	waiters(1)
	rotated := make(chan error, 1)
	go func() {
		key := "new-provider-key"
		_, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: config.Revision, Enabled: true, Provider: "openai", Model: "test-model", BaseURL: "https://provider.example.test", APIKey: &key})
		rotated <- err
	}()
	waiters(2)
	if err := blocker.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-sent; err != nil {
		t.Fatalf("accepted turn lost its credential: %v", err)
	}
	if err := <-rotated; err != nil {
		t.Fatal(err)
	}
	var retained bool
	if err := f.db.QueryRow(t.Context(), "SELECT EXISTS(SELECT 1 FROM chat_turns t JOIN chat_credentials c ON c.id=t.credential_id WHERE t.conversation_id=$1 AND c.id=$2)", conversation.ID, config.CredentialID).Scan(&retained); err != nil {
		t.Fatal(err)
	}
	if !retained {
		t.Fatal("rotation removed an accepted turn's credential")
	}
}

func TestChatConversationCreationIsIdempotentConcurrently(t *testing.T) {
	f := newChatFixture(t)
	request := uuid.NewString()
	start := make(chan struct{})
	type result struct {
		conversation m.ChatConversation
		err          error
	}
	results := make(chan result, 2)
	for i := 0; i < 2; i++ {
		go func() {
			<-start
			conversation, err := f.source.CreateConversation(t.Context(), f.actor, request)
			results <- result{conversation, err}
		}()
	}
	close(start)
	first, second := <-results, <-results
	if first.err != nil || second.err != nil || first.conversation.ID != second.conversation.ID {
		t.Fatalf("concurrent request replay diverged: %+v %+v", first, second)
	}
}

func TestChatOwnerQuotaSurvivesConcurrentAcceptance(t *testing.T) {
	f := newChatFixture(t)
	for i := 0; i < 9; i++ {
		conversation := f.conversation()
		f.send(conversation.ID, "Existing accepted turn")
	}
	first, second := f.conversation(), f.conversation()
	start, results := make(chan struct{}), make(chan error, 2)
	for _, conversation := range []m.ChatConversation{first, second} {
		go func() {
			<-start
			_, err := f.source.Send(t.Context(), f.actor, conversation.ID, m.ChatSendInput{RequestID: uuid.NewString(), Content: "Last available owner slot"})
			results <- err
		}()
	}
	close(start)
	winners := 0
	for i := 0; i < 2; i++ {
		if err := <-results; err == nil {
			winners++
		} else if !errors.Is(err, m.ErrBusy) {
			t.Fatal(err)
		}
	}
	var count int
	if err := f.db.QueryRow(t.Context(), "SELECT count(*) FROM chat_turns WHERE owner_id=$1 AND status IN ('queued','running')", f.actor.UserID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if winners != 1 || count != 10 {
		t.Fatalf("owner quota raced: winners=%d accepted=%d", winners, count)
	}
}
