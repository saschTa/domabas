//go:build integration

package postgres

import (
	"testing"
	"testing/fstest"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func TestChatProgressMigrationPreservesRepliesAndBackfillsContinuations(t *testing.T) {
	source := migrationSource(t, testdb.New(t))
	files := fstest.MapFS{}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() >= "028" {
			continue
		}
		name := "migrations/" + entry.Name()
		contents, err := migrations.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		files[name] = &fstest.MapFile{Data: contents}
	}
	if err := source.migrate(t.Context(), files); err != nil {
		t.Fatal(err)
	}
	account, user, conversation, turn, document := uuid.New(), uuid.New(), uuid.New(), uuid.New(), uuid.New()
	migrationSQL(t, source, "INSERT INTO accounts(id,name) VALUES($1,'Retained chat')", account)
	migrationSQL(t, source, "WITH new_user AS (INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,'retained-chat@example.test','unused',$2) RETURNING id) INSERT INTO memberships(account_id,user_id,role,is_owner) SELECT $2,id,'admin',true FROM new_user", user, account)
	migrationSQL(t, source, "INSERT INTO chat_conversations(id,account_id,owner_id,request_id) VALUES($1,$2,$3,$4)", conversation, account, user, uuid.New())
	migrationSQL(t, source, "INSERT INTO chat_turns(id,conversation_id,account_id,owner_id,request_id,credential_revision,content_hash,configuration_revision,provider,model,base_url,internal_runtime,workflow_id,task_queue) VALUES($1,$2,$3,$4,$5,1,''::bytea,1,'ollama','gemma3:4b','',true,'migration-test','migration-test')", turn, conversation, account, user, uuid.New())
	examples := []struct {
		kind, query, body, outcome string
		next                       int
	}{
		{"list_tools", "", `{"items":[{"name":"list_tools"}],"nextOffset":2}`, "progress", 2},
		{"search_documents", "invoice", `{"items":[{"title":"Invoice"}],"nextOffset":10}`, "progress", 10},
		{"read_document", "", `{"text":"Invoice evidence","nextOffset":8000}`, "progress", 8000},
		{"search_documents", "bill", `{"items":[{"title":"Invoice"}]}`, "no_new_evidence", 0},
		{"read_document", "", `{"text":"Invoice evidence","nextOffset":8000}`, "no_new_evidence", 8000},
		{"search_documents", "missing", `{"items":[]}`, "empty_result", 0},
		{"read_document", "", `{"error":"document_unavailable"}`, "document_unavailable", 0},
	}
	for ordinal, example := range examples {
		var doc any
		if example.kind == "read_document" {
			doc = document
		}
		migrationSQL(t, source, "INSERT INTO chat_tool_results(turn_id,ordinal,kind,query,document_id,result_text) VALUES($1,$2,$3,$4,$5,$6)", turn, ordinal, example.kind, example.query, doc, example.body)
		if ordinal == 1 || ordinal == 3 {
			migrationSQL(t, source, "INSERT INTO chat_sources(turn_id,ordinal,document_id,title) VALUES($1,$2,$3,'Invoice')", turn, ordinal, document)
		}
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	var retainedContext, defaultContext int
	if err := source.pool.QueryRow(t.Context(), "SELECT context_length FROM chat_turns WHERE id=$1", turn).Scan(&retainedContext); err != nil {
		t.Fatal(err)
	}
	if err := source.pool.QueryRow(t.Context(), "SELECT context_length FROM chat_configuration WHERE singleton").Scan(&defaultContext); err != nil {
		t.Fatal(err)
	}
	if retainedContext != 16384 || defaultContext != 32768 {
		t.Fatalf("context migration changed accepted work or current default: retained=%d current=%d", retainedContext, defaultContext)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	for ordinal, example := range examples {
		var body, outcome string
		var next *int
		if err := source.pool.QueryRow(t.Context(), "SELECT result_text,outcome_code,next_offset FROM chat_tool_results WHERE turn_id=$1 AND ordinal=$2", turn, ordinal).Scan(&body, &outcome, &next); err != nil {
			t.Fatal(err)
		}
		if body != example.body || outcome != example.outcome || (example.next == 0 && next != nil) || (example.next != 0 && (next == nil || *next != example.next)) {
			t.Fatalf("row %d changed snapshot or lost metadata: %s %s %v", ordinal, body, outcome, next)
		}
	}
}
