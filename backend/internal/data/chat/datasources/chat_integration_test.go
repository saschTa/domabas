//go:build integration

package datasources

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	data "github.com/domabas/domabas/backend/internal/data/chat/models"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	identitycontainer "github.com/domabas/domabas/backend/internal/bootstrap/identity"
	chatprovider "github.com/domabas/domabas/backend/internal/data/chat/datasources/provider"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	schedulersources "github.com/domabas/domabas/backend/internal/data/scheduler/datasources"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	chatservices "github.com/domabas/domabas/backend/internal/domain/chat/services"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"time"
)

type chatServiceFixture struct {
	*chatservices.ChatService
	*chatservices.ChatExecutionService
}

type chatFixture struct {
	t        *testing.T
	db       *pgx.Conn
	source   *chatServiceFixture
	actor    m.ChatActor
	keyPath  string
	database *postgres.PostgresDataSource
}

func newChatFixture(t *testing.T) *chatFixture {
	t.Helper()
	url := testdb.New(t)
	database, err := postgres.NewPostgresDataSource(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(database.Close)
	if err := database.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	db, err := pgx.Connect(t.Context(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close(context.Background()) })
	identities, err := identitycontainer.NewIdentityContainer(database.Database(), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	scheduler := schedulersources.NewSchedulerDataSource(database.Database(), 512, "http://ollama.test:11434")
	if err := scheduler.Initialize(t.Context()); err != nil {
		t.Fatal(err)
	}
	keyPath := filepath.Join(t.TempDir(), "secrets", "chat.key")
	source, err := NewChatDataSource(t.Context(), database.Database(), keyPath, "chat-test-"+uuid.NewString(), scheduler)
	if err != nil {
		t.Fatal(err)
	}
	remote, err := chatprovider.NewChatProviderRemoteDataSource("http://ollama.test:11434")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(remote.Close)
	f := &chatFixture{t: t, db: db, source: &chatServiceFixture{ChatService: chatservices.NewChatService(source, remote, remote, identities.Service()), ChatExecutionService: chatservices.NewChatExecutionService(source, nil, identities.Service())}, keyPath: keyPath, database: database}
	f.actor = f.newActor()
	return f
}
func (f *chatFixture) exec(sql string, args ...any) {
	f.t.Helper()
	if _, err := f.db.Exec(f.t.Context(), sql, args...); err != nil {
		f.t.Fatal(err)
	}
}
func (f *chatFixture) newActor() m.ChatActor {
	f.t.Helper()
	a := m.ChatActor{AccountID: uuid.NewString(), UserID: uuid.NewString(), SessionDigest: strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", ""), CredentialRevision: 1}
	f.exec("BEGIN")
	f.exec("INSERT INTO accounts(id,name) VALUES($1,'Chat test')", a.AccountID)
	f.exec("INSERT INTO users(id,email,password_hash,personal_account_id,system_role) VALUES($1,$2,'unused',$3,'admin')", a.UserID, a.UserID+"@example.test", a.AccountID)
	f.exec("INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',true)", a.AccountID, a.UserID)
	f.exec("INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", a.SessionDigest, a.AccountID, a.UserID)
	f.exec("COMMIT")
	return a
}
func (f *chatFixture) conversation() m.ChatConversation {
	f.t.Helper()
	v, err := f.source.CreateConversation(f.t.Context(), f.actor, uuid.NewString())
	if err != nil {
		f.t.Fatal(err)
	}
	return v
}
func (f *chatFixture) send(id, content string) m.ChatSendResult {
	f.t.Helper()
	v, err := f.source.Send(f.t.Context(), f.actor, id, m.ChatSendInput{RequestID: uuid.NewString(), Content: content})
	if err != nil {
		f.t.Fatal(err)
	}
	return v
}

func TestChatPrivateAcceptanceSettingsAndCredentials(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	c, err := f.source.Configuration(ctx, f.actor, true)
	if err != nil || !c.Enabled || c.Model != "qwen3.5:4b" || c.Provider != "ollama" {
		t.Fatal(c, err)
	}
	key := "very-private-chat-key"
	c, err = f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: c.Revision, Enabled: true, Provider: "openai", Model: "fixture", BaseURL: "https://external.test/v1", APIKey: &key})
	if err != nil || !c.HasAPIKey || c.InternalRuntime {
		t.Fatal(c, err)
	}
	var encrypted []byte
	if err := f.db.QueryRow(ctx, "SELECT encrypted_key FROM chat_credentials WHERE id=$1", c.CredentialID).Scan(&encrypted); err != nil || bytes.Contains(encrypted, []byte(key)) {
		t.Fatal("secret not encrypted", err)
	}
	if _, err := CredentialKey(ctx, f.database.Database(), "", f.keyPath); err != nil {
		t.Fatal(err)
	}
	public, err := f.source.Configuration(ctx, f.actor, false)
	if err != nil || public.BaseURL != "" || public.CredentialID != "" || public.HasAPIKey {
		t.Fatal("private configuration leaked", public, err)
	}
	request := uuid.NewString()
	conversation, err := f.source.CreateConversation(ctx, f.actor, request)
	if err != nil {
		t.Fatal(err)
	}
	again, err := f.source.CreateConversation(ctx, f.actor, request)
	if err != nil || again.ID != conversation.ID {
		t.Fatal("create not idempotent", err)
	}
	input := m.ChatSendInput{RequestID: uuid.NewString(), Content: "Find electricity invoices"}
	sent, err := f.source.Send(ctx, f.actor, conversation.ID, input)
	if err != nil {
		t.Fatal(err)
	}
	repeat, err := f.source.Send(ctx, f.actor, conversation.ID, input)
	if err != nil || repeat.UserMessage.ID != sent.UserMessage.ID || repeat.AssistantMessage.ID != sent.AssistantMessage.ID {
		t.Fatal("send not idempotent", err)
	}
	input.Content = "different"
	if _, err := f.source.Send(ctx, f.actor, conversation.ID, input); !errors.Is(err, m.ErrConflict) {
		t.Fatal("mismatched intent accepted", err)
	}
	other := f.newActor()
	if _, err := f.source.Messages(ctx, other, conversation.ID, m.ChatPageRequest{}); !errors.Is(err, m.ErrNotFound) {
		t.Fatal("foreign chat visible", err)
	}
	f.exec("INSERT INTO memberships(account_id,user_id,role,is_owner) VALUES($1,$2,'admin',false)", f.actor.AccountID, other.UserID)
	shared := other
	shared.AccountID = f.actor.AccountID
	shared.SessionDigest = strings.ReplaceAll(uuid.NewString()+uuid.NewString(), "-", "")
	f.exec("INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", shared.SessionDigest, shared.AccountID, shared.UserID)
	if _, err := f.source.Messages(ctx, shared, conversation.ID, m.ChatPageRequest{}); !errors.Is(err, m.ErrNotFound) {
		t.Fatal("same-library administrator saw private chat", err)
	}
	cancelled, err := f.source.Cancel(ctx, f.actor, conversation.ID, sent.AssistantMessage.TurnID)
	if err != nil || cancelled.Status != "cancelled" {
		t.Fatal(cancelled, err)
	}
	if _, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: 1, Enabled: true, Provider: "ollama", Model: "qwen3.5:4b"}); !errors.Is(err, m.ErrConflict) {
		t.Fatal("stale settings save accepted", err)
	}
	updated, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: c.Revision, Enabled: false, Provider: "openai", Model: "fixture", BaseURL: "https://another.test/v1"})
	if err != nil || updated.HasAPIKey {
		t.Fatal("endpoint change retained secret", updated, err)
	}
	if _, err := f.source.Send(ctx, f.actor, conversation.ID, m.ChatSendInput{RequestID: uuid.NewString(), Content: "disabled"}); !errors.Is(err, m.ErrDisabled) {
		t.Fatal("disabled send accepted", err)
	}
	if page, err := f.source.Messages(ctx, f.actor, conversation.ID, m.ChatPageRequest{}); err != nil || len(page.Items) != 2 {
		t.Fatal("disabled history unavailable", page, err)
	}
	if err := os.Rename(f.keyPath, f.keyPath+".backup"); err != nil {
		t.Fatal(err)
	}
	if _, err := CredentialKey(ctx, f.database.Database(), "", f.keyPath); err == nil {
		t.Fatal("missing retained credential key regenerated")
	}
}

func TestChatDurableConsentRevisionAndDeleteFence(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	sent := f.send(conversation.ID, "durable prompt")
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal(err)
	}
	f.exec("DELETE FROM sessions WHERE digest=$1", f.actor.SessionDigest)
	if _, err := f.source.Work(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal("ordinary logout removed durable consent", err)
	}
	f.exec("UPDATE users SET credential_revision=credential_revision+1 WHERE id=$1", f.actor.UserID)
	if _, err := f.source.Work(ctx, sent.AssistantMessage.TurnID, token); !errors.Is(err, m.ErrForbidden) {
		t.Fatal("changed user revision retained consent", err)
	}
	f.exec("UPDATE users SET credential_revision=credential_revision-1 WHERE id=$1", f.actor.UserID)
	f.exec("INSERT INTO sessions(digest,account_id,user_id,credential_revision) VALUES($1,$2,$3,1)", f.actor.SessionDigest, f.actor.AccountID, f.actor.UserID)
	if err := f.source.DeleteConversation(ctx, f.actor, conversation.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Complete(ctx, sent.AssistantMessage.TurnID, token, "late private answer"); !errors.Is(err, m.ErrNotFound) {
		t.Fatal("deleted turn published", err)
	}
	var retained bool
	if err := f.db.QueryRow(ctx, "SELECT NOT execution_closed FROM chat_turns WHERE id=$1", sent.AssistantMessage.TurnID).Scan(&retained); err != nil || !retained {
		t.Fatal("deletion lost execution evidence", retained, err)
	}
	var body string
	if err := f.db.QueryRow(ctx, "SELECT content FROM chat_messages WHERE id=$1", sent.UserMessage.ID).Scan(&body); err != nil || body == "" {
		t.Fatal("deleted execution scrubbed before drain", err)
	}
	if err := f.source.Release(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal(err)
	}
	f.exec("UPDATE chat_turns SET delivery_expires_at=clock_timestamp()-interval '1 second',next_check_at=clock_timestamp() WHERE id=$1", sent.AssistantMessage.TurnID)
	dispatch, err := f.source.Dispatch(ctx)
	if err != nil || len(dispatch) != 1 {
		t.Fatal(dispatch, err)
	}
	if err := f.source.Closed(ctx, dispatch[0], "chat_cancelled"); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(ctx, "SELECT content FROM chat_messages WHERE id=$1", sent.UserMessage.ID).Scan(&body); err != nil || body != "" {
		t.Fatal("deleted contents retained after drain", body, err)
	}
}

func TestChatAcceptanceRollbackAndImmutableProviderCredentials(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	request := m.ChatSendInput{RequestID: uuid.NewString(), Content: "rollback prompt"}
	f.exec("ALTER TABLE chat_messages ADD CONSTRAINT test_reject_prompt CHECK(content<>'rollback prompt')")
	if _, err := f.source.Send(ctx, f.actor, conversation.ID, request); err == nil {
		t.Fatal("fixture did not reject write")
	}
	var turns, messages int
	var sequence int64
	if err := f.db.QueryRow(ctx, "SELECT (SELECT count(*) FROM chat_turns),(SELECT count(*) FROM chat_messages),next_sequence FROM chat_conversations WHERE id=$1", conversation.ID).Scan(&turns, &messages, &sequence); err != nil || turns != 0 || messages != 0 || sequence != 1 {
		t.Fatal("acceptance not atomic", turns, messages, sequence, err)
	}
	f.exec("ALTER TABLE chat_messages DROP CONSTRAINT test_reject_prompt")
	firstKey := "first-provider-secret"
	configuration, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: 1, Enabled: true, Provider: "openai", Model: "first-model", BaseURL: "http://ollama.test:11434/v1", APIKey: &firstKey})
	if err != nil || !configuration.InternalRuntime {
		t.Fatal("same origin was not classified as the shared Ollama resource", configuration, err)
	}
	sent, err := f.source.Send(ctx, f.actor, conversation.ID, request)
	if err != nil {
		t.Fatal(err)
	}
	secondKey := "second-provider-secret"
	if _, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: configuration.Revision, Enabled: false, Provider: "openai", Model: "second-model", BaseURL: "https://independent.test/v1", APIKey: &secondKey}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal(err)
	}
	work, err := f.source.Work(ctx, sent.AssistantMessage.TurnID, token)
	if err != nil || work.Configuration.Model != "first-model" || work.APIKey != firstKey || !work.Configuration.InternalRuntime {
		t.Fatal("accepted settings changed", work.Configuration, err)
	}
}

func TestChatStepAcquisitionReplaysCompletionWithoutReplacingOwnership(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	turn := f.send(conversation.ID, "Replay a committed answer").AssistantMessage.TurnID
	token := uuid.NewString()
	if completed, err := f.source.AcquireStep(ctx, turn, token); completed || !errors.Is(err, m.ErrCancelled) {
		t.Fatal("non-admitted step acquired", completed, err)
	}
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	if completed, err := f.source.AcquireStep(ctx, turn, token); completed || err != nil {
		t.Fatal("admitted step not acquired", completed, err)
	}
	if completed, err := f.source.AcquireStep(ctx, turn, uuid.NewString()); completed || err == nil {
		t.Fatal("overlapping step acquired", completed, err)
	}
	if err := f.source.Complete(ctx, turn, token, "Retained answer"); err != nil {
		t.Fatal(err)
	}
	if completed, err := f.source.AcquireStep(ctx, turn, uuid.NewString()); !completed || err != nil {
		t.Fatal("committed answer not replayed", completed, err)
	}
	var retainedToken, content string
	if err := f.db.QueryRow(ctx, "SELECT t.execution_token::text,m.content FROM chat_turns t JOIN chat_messages m ON m.turn_id=t.id AND m.role='assistant' WHERE t.id=$1", turn).Scan(&retainedToken, &content); err != nil || retainedToken != token || content != "Retained answer" {
		t.Fatal("completion replay changed persisted ownership or content", retainedToken, content, err)
	}
	if err := f.source.Acquire(ctx, turn, uuid.NewString()); !errors.Is(err, m.ErrCancelled) {
		t.Fatal("legacy acquisition behavior changed", err)
	}
	if err := f.source.Release(ctx, turn, token); err != nil {
		t.Fatal(err)
	}
	if completed, err := f.source.AcquireStep(ctx, turn, uuid.NewString()); !completed || err != nil {
		t.Fatal("drained completion not replayed", completed, err)
	}
}

func TestChatPaginationToolsFencesAndRetainedAuthority(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	for i := 0; i < 13; i++ {
		sent := f.send(conversation.ID, "earlier prompt")
		if err := f.source.Fail(ctx, sent.AssistantMessage.TurnID, "provider_unavailable"); err != nil {
			t.Fatal(err)
		}
	}
	page, err := f.source.Messages(ctx, f.actor, conversation.ID, m.ChatPageRequest{Limit: 20})
	if err != nil || len(page.Items) != 20 || page.NextCursor == "" {
		t.Fatal(page, err)
	}
	older, err := f.source.Messages(ctx, f.actor, conversation.ID, m.ChatPageRequest{Limit: 20, Cursor: page.NextCursor})
	if err != nil || len(older.Items) != 6 || older.Items[0].Sequence >= page.Items[len(page.Items)-1].Sequence {
		t.Fatal(older, err)
	}
	sent := f.send(conversation.ID, "Find electricity")
	turn := sent.AssistantMessage.TurnID
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, turn, token); !errors.Is(err, m.ErrCancelled) {
		t.Fatal("non-admitted work acquired", err)
	}
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Acquire(ctx, turn, token); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Acquire(ctx, turn, uuid.NewString()); err == nil {
		t.Fatal("overlapping activity acquired")
	}
	doc := uuid.NewString()
	foreign := f.newActor()
	foreignDoc := uuid.NewString()
	f.exec("INSERT INTO documents(id,account_id,title,description,ocr_machine_text,created_at) VALUES($1,$2,'Electricity invoice','','Electricity amount 42 euros',clock_timestamp()),($3,$4,'Electricity private','','Foreign secret',clock_timestamp())", doc, f.actor.AccountID, foreignDoc, foreign.AccountID)
	tool, err := f.source.Tool(ctx, turn, token, 0, m.ChatAction{Kind: "search_documents", Query: "electricity", ToolCallID: "search-1"})
	if err != nil || len(tool.Sources) != 1 || tool.Sources[0].DocumentID != doc || strings.Contains(tool.Content, "Foreign") {
		t.Fatal(tool, err)
	}
	read, err := f.source.Tool(ctx, turn, token, 1, m.ChatAction{Kind: "read_document", DocumentID: doc, ToolCallID: "read-1"})
	if err != nil || !strings.Contains(read.Content, "42 euros") {
		t.Fatal(read, err)
	}
	work, err := f.source.Work(ctx, turn, token)
	if err != nil || len(work.Tools) != 2 {
		t.Fatal(work, err)
	}
	if err := f.source.Complete(ctx, turn, uuid.NewString(), "stale"); !errors.Is(err, m.ErrCancelled) {
		t.Fatal("stale publish", err)
	}
	if _, err := f.source.Cancel(ctx, f.actor, conversation.ID, turn); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Complete(ctx, turn, token, "late answer"); !errors.Is(err, m.ErrCancelled) {
		t.Fatal("cancelled publish", err)
	}
	second := f.send(conversation.ID, "Use the earlier source")
	secondToken := uuid.NewString()
	f.exec("UPDATE chat_turns SET execution_closed=true WHERE id=$1", turn)
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Acquire(ctx, second.AssistantMessage.TurnID, secondToken); err != nil {
		t.Fatal(err)
	}
	if _, err := f.source.Tool(ctx, second.AssistantMessage.TurnID, secondToken, 0, m.ChatAction{Kind: "search_documents", Query: "electricity"}); err != nil {
		t.Fatal(err)
	}
	f.exec("DELETE FROM documents WHERE id=$1", doc)
	if _, err := f.source.Work(ctx, second.AssistantMessage.TurnID, secondToken); err == nil {
		t.Fatal("deleted context transmitted")
	}
}

func TestChatConcurrentAcceptanceAndDispatchCapacity(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := f.source.Send(ctx, f.actor, conversation.ID, m.ChatSendInput{RequestID: uuid.NewString(), Content: "competing prompt"})
			results <- err
		}()
	}
	wg.Wait()
	close(results)
	success := 0
	for err := range results {
		if err == nil {
			success++
		} else if !errors.Is(err, m.ErrConflict) {
			t.Fatal(err)
		}
	}
	if success != 1 {
		t.Fatal("active turn race", success)
	}
	f.send(f.conversation().ID, "second internal")
	f.send(f.conversation().ID, "third internal")
	config, err := f.source.Configuration(ctx, f.actor, true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: config.Revision, Enabled: true, Provider: "openai", Model: "external", BaseURL: "http://external.test/v1"}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		f.send(f.conversation().ID, "external prompt")
	}
	var batches [][]m.ChatDispatch
	var mu sync.Mutex
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			v, err := f.source.Dispatch(ctx)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				t.Error(err)
			}
			batches = append(batches, v)
		}()
	}
	wg.Wait()
	var claimed []m.ChatDispatch
	for _, batch := range batches {
		claimed = append(claimed, batch...)
	}
	if len(claimed) != 3 {
		t.Fatal("capacity not deployment bounded", len(claimed))
	}
	var internal, external int
	if err := f.db.QueryRow(ctx, "SELECT count(*) FILTER(WHERE internal_runtime),count(*) FILTER(WHERE NOT internal_runtime) FROM chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed").Scan(&internal, &external); err != nil || internal != 1 || external != 2 {
		t.Fatal(internal, external, err)
	}
	d := claimed[0]
	if err := f.source.Acknowledge(ctx, d, "test-run"); err != nil {
		t.Fatal(err)
	}
	f.exec("UPDATE chat_turns SET next_check_at=clock_timestamp() WHERE id=$1", d.TurnID)
	refreshed, err := f.source.Dispatch(ctx)
	if err != nil || len(refreshed) != 1 {
		t.Fatal(refreshed, err)
	}
	d = refreshed[0]
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, d.TurnID, token); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Closed(ctx, d, "execution_lost"); err != nil {
		t.Fatal(err)
	}
	var closed bool
	if err := f.db.QueryRow(ctx, "SELECT execution_closed FROM chat_turns WHERE id=$1", d.TurnID).Scan(&closed); err != nil || closed {
		t.Fatal("released undrained permit", closed, err)
	}
	if err := f.source.Release(ctx, d.TurnID, token); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Closed(ctx, d, "execution_lost"); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(ctx, "SELECT execution_closed FROM chat_turns WHERE id=$1", d.TurnID).Scan(&closed); err != nil || !closed {
		t.Fatal("drained permit retained", closed, err)
	}
}

func TestChatCredentialRotationRemovesOnlyUnreferencedSecrets(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	revision := int64(1)
	save := func(key string) m.ChatConfiguration {
		t.Helper()
		c, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: revision, Enabled: true, Provider: "openai", Model: "fixture", BaseURL: "https://chat.example.test/v1", APIKey: &key})
		if err != nil {
			t.Fatal(err)
		}
		revision = c.Revision
		return c
	}
	exists := func(id string) bool {
		t.Helper()
		var present bool
		if err := f.db.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM chat_credentials WHERE id=$1)", id).Scan(&present); err != nil {
			t.Fatal(err)
		}
		return present
	}
	unused := save("unused-secret")
	used := save("accepted-turn-secret")
	if exists(unused.CredentialID) {
		t.Fatal("rotation retained unused ciphertext")
	}
	sent := f.send(f.conversation().ID, "keep my accepted credential")
	replacement := save("replacement-secret")
	if !exists(used.CredentialID) {
		t.Fatal("rotation erased an accepted turn credential")
	}
	cleared, err := f.source.UpdateConfiguration(ctx, f.actor, m.ChatConfigurationUpdate{ExpectedRevision: revision, Enabled: true, Provider: "openai", Model: "fixture", BaseURL: "https://chat.example.test/v1", ClearAPIKey: true})
	if err != nil || cleared.HasAPIKey {
		t.Fatal(cleared, err)
	}
	if exists(replacement.CredentialID) || !exists(used.CredentialID) {
		t.Fatal("clearing did not distinguish used and unused credentials")
	}
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	token := uuid.NewString()
	if err := f.source.Acquire(ctx, sent.AssistantMessage.TurnID, token); err != nil {
		t.Fatal(err)
	}
	work, err := f.source.Work(ctx, sent.AssistantMessage.TurnID, token)
	if err != nil || work.APIKey != "accepted-turn-secret" {
		t.Fatal("accepted secret no longer usable", err)
	}
}

func TestChatCatalogPagesReplayAndThirtyPersistedCalls(t *testing.T) {
	f := newChatFixture(t)
	ctx := t.Context()
	conversation := f.conversation()
	sent := f.send(conversation.ID, "Discover tools")
	turn := sent.AssistantMessage.TurnID
	token := uuid.NewString()
	if _, err := f.source.Dispatch(ctx); err != nil {
		t.Fatal(err)
	}
	if err := f.source.Acquire(ctx, turn, token); err != nil {
		t.Fatal(err)
	}
	document := uuid.NewString()
	f.exec("INSERT INTO documents(id,account_id,title,description,ocr_machine_text,created_at) VALUES($1,$2,'Long evidence document','',$3,clock_timestamp())", document, f.actor.AccountID, strings.Repeat("e", 27*8000))
	for ordinal := 0; ordinal < m.ChatMaxToolCalls; ordinal++ {
		action := m.ChatAction{Kind: "list_tools", Offset: ordinal * 2, ToolCallID: fmt.Sprintf("call-%d", ordinal)}
		if ordinal == 2 {
			action = m.ChatAction{Kind: "search_documents", Query: "Long evidence", ToolCallID: action.ToolCallID}
		} else if ordinal > 2 {
			action = m.ChatAction{Kind: "read_document", DocumentID: document, Offset: (ordinal - 3) * 8000, ToolCallID: action.ToolCallID}
		}
		result, err := f.source.Tool(ctx, turn, token, ordinal, action)
		if err != nil || result.Outcome != "progress" {
			t.Fatal(ordinal, err, result.Outcome)
		}
		if ordinal < 2 && len(result.Sources) != 0 {
			t.Fatal("catalog manufactured document sources")
		}
		var page data.ChatToolCatalogPage
		if ordinal < 2 {
			if err := json.Unmarshal([]byte(result.Content), &page); err != nil {
				t.Fatal(err)
			}
		}
		switch ordinal {
		case 0:
			if len(page.Items) != 2 || page.Items[0].Name != "list_tools" || page.Items[1].Name != "search_documents" || page.NextOffset == nil || *page.NextOffset != 2 {
				t.Fatal(page)
			}
		case 1:
			if len(page.Items) != 1 || page.Items[0].Name != "read_document" || page.NextOffset != nil {
				t.Fatal(page)
			}
		}
		replay, err := f.source.Tool(ctx, turn, token, ordinal, action)
		if err != nil || replay.Content != result.Content || replay.Outcome != result.Outcome || len(replay.Sources) != len(result.Sources) {
			t.Fatal("snapshot replay", err)
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
	if err != nil || len(work.Tools) != 30 {
		t.Fatal("recovery lost budget", len(work.Tools), err)
	}
	_, err = f.source.Tool(ctx, turn, token, 30, m.ChatAction{Kind: "list_tools"})
	var failure m.ChatProcessingError
	if !errors.As(err, &failure) || failure.Code != "tool_limit" {
		t.Fatal("31st tool was not rejected", err)
	}
	if err := f.source.Complete(ctx, turn, token, "All available tools inspected."); err != nil {
		t.Fatal("final answer after 30 calls", err)
	}
}

func TestChatResourceCandidateScanDiscoversEndpointBeyondBlockedPage(t *testing.T) {
	f := newChatFixture(t)
	configure := func(endpoint string) {
		current, err := f.source.Configuration(t.Context(), f.actor, true)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = f.source.UpdateConfiguration(t.Context(), f.actor, m.ChatConfigurationUpdate{ExpectedRevision: current.Revision, Enabled: true, Provider: "openai", Model: "fixture-model", BaseURL: endpoint}); err != nil {
			t.Fatal(err)
		}
	}
	configure("https://endpoint-a.example.test/v1")
	for i := range 22 {
		if i%8 == 0 {
			f.actor = f.newActor()
		}
		f.send(f.conversation().ID, "Endpoint A contention")
	}
	configure("https://endpoint-b.example.test/v1")
	later := f.send(f.conversation().ID, "Independent endpoint B")
	found := false
	for range 3 {
		dispatches, err := f.source.Dispatch(t.Context())
		if err != nil {
			t.Fatal(err)
		}
		for _, dispatch := range dispatches {
			found = found || dispatch.TurnID == later.AssistantMessage.TurnID
		}
	}
	if !found {
		t.Fatal("twenty blocked turns hid an available independent provider")
	}
	var first, second int
	if err := f.db.QueryRow(t.Context(), `SELECT count(*) FILTER(WHERE base_url='https://endpoint-a.example.test/v1'),count(*) FILTER(WHERE base_url='https://endpoint-b.example.test/v1') FROM chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed`).Scan(&first, &second); err != nil || first != 2 || second != 1 {
		t.Fatal("endpoint resource limits not preserved", first, second, err)
	}
}
