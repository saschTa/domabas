//go:build integration

package datasources_test

import (
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
	"github.com/google/uuid"
)

func TestRealtimePaperlessRunAndItemProgress(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	f.capture(t, false, `UPDATE memberships SET claims=claims||ARRAY['paperless:import','documents:upload'] WHERE account_id=$1 AND user_id=$2`, f.account, f.owner.UserID)
	id := uuid.NewString()
	signals := f.capture(t, false, `INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue) VALUES($1,$2,$3,1,'https://example.test','test','realtime-test')`, id, f.account, f.owner.UserID)
	f.wantTopics(t, f.owner, signals, m.Paperless)
	f.wantTopics(t, f.peer, signals)
	f.wantTopics(t, f.manager, signals)
	f.wantTopics(t, f.outsider, signals)
	signals = f.capture(t, false, `INSERT INTO paperless_items(run_id,source_id,title) VALUES($1,1,'Private title')`, id)
	f.wantTopics(t, f.owner, signals, m.Paperless)
	signals = f.capture(t, false, `UPDATE paperless_items SET status='imported' WHERE run_id=$1`, id)
	f.wantTopics(t, f.owner, signals, m.Paperless)
	signals = f.capture(t, false, `UPDATE paperless_runs SET state='succeeded',stage='complete' WHERE id=$1`, id)
	f.wantTopics(t, f.owner, signals, m.Paperless)
	if signals := f.capture(t, false, `UPDATE paperless_runs SET next_check_at=clock_timestamp() WHERE id=$1`, id); len(signals) != 0 {
		t.Fatalf("bookkeeping emitted: %+v", signals)
	}
	if signals := f.capture(t, true, `UPDATE paperless_items SET status='failed' WHERE run_id=$1`, id); len(signals) != 0 {
		t.Fatalf("rollback emitted: %+v", signals)
	}
	f.capture(t, false, `UPDATE memberships SET claims=ARRAY['documents:jobs:read'] WHERE account_id=$1 AND user_id=$2`, f.account, f.owner.UserID)
	f.wantTopics(t, f.owner, signals)
}

func TestRealtimeChatProgressAndMessages(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	f.capture(t, false, `UPDATE memberships SET claims=claims||ARRAY['chat:use'] WHERE account_id=$1 AND user_id=$2`, f.account, f.owner.UserID)
	conversation, turn, message := uuid.NewString(), uuid.NewString(), uuid.NewString()
	signals := f.capture(t, false, `INSERT INTO chat_conversations(id,account_id,owner_id,request_id) VALUES($1,$2,$3,$1)`, conversation, f.account, f.owner.UserID)
	f.wantTopics(t, f.owner, signals, m.Chat)
	f.wantTopics(t, f.peer, signals)
	f.wantTopics(t, f.manager, signals)
	f.wantTopics(t, f.outsider, signals)
	signals = f.capture(t, false, `INSERT INTO chat_turns(id,conversation_id,account_id,owner_id,request_id,credential_revision,content_hash,configuration_revision,provider,model,base_url,internal_runtime,workflow_id,task_queue) VALUES($1::uuid,$2,$3,$4,$1::uuid,1,'test',1,'ollama','test','',true,$1::text,'realtime-test')`, turn, conversation, f.account, f.owner.UserID)
	f.wantTopics(t, f.owner, signals, m.Chat)
	signals = f.capture(t, false, `INSERT INTO chat_messages(id,conversation_id,turn_id,sequence,role,content) VALUES($1,$2,$3,1,'assistant','Partial answer')`, message, conversation, turn)
	f.wantTopics(t, f.owner, signals, m.Chat)
	signals = f.capture(t, false, `UPDATE chat_messages SET content='Finished answer' WHERE id=$1`, message)
	f.wantTopics(t, f.owner, signals, m.Chat)
	signals = f.capture(t, false, `INSERT INTO chat_tool_results(turn_id,ordinal,kind,result_text) VALUES($1,0,'search_documents','results')`, turn)
	f.wantTopics(t, f.owner, signals, m.Chat)
	signals = f.capture(t, false, `UPDATE chat_tool_results SET outcome_code='empty_result' WHERE turn_id=$1`, turn)
	f.wantTopics(t, f.owner, signals, m.Chat)
	signals = f.capture(t, false, `INSERT INTO chat_sources(turn_id,ordinal,document_id,title) VALUES($1,0,$2,'Private source')`, turn, uuid.NewString())
	f.wantTopics(t, f.owner, signals, m.Chat)
	f.wantTopics(t, f.peer, signals)
	signals = f.capture(t, false, `UPDATE chat_sources SET excerpt='Updated excerpt' WHERE turn_id=$1`, turn)
	f.wantTopics(t, f.owner, signals, m.Chat)
	signals = f.capture(t, false, `UPDATE chat_turns SET status='completed',stage='complete',finished_at=clock_timestamp() WHERE id=$1`, turn)
	f.wantTopics(t, f.owner, signals, m.Chat)
	if signals := f.capture(t, false, `UPDATE chat_turns SET next_check_at=clock_timestamp() WHERE id=$1`, turn); len(signals) != 0 {
		t.Fatalf("bookkeeping emitted: %+v", signals)
	}
	if signals := f.capture(t, true, `UPDATE chat_messages SET content='Rolled back' WHERE id=$1`, message); len(signals) != 0 {
		t.Fatalf("rollback emitted: %+v", signals)
	}
}

func TestRealtimeAutomaticNamespaceBatchesReachReadersAndAdministrators(t *testing.T) {
	f := newIndependentRealtimeFixture(t)
	f.capture(t, false, `UPDATE users SET system_role='admin' WHERE id=$1`, f.manager.UserID)
	signals := f.capture(t, false, `INSERT INTO document_reindex_batches(id,account_id,reason,configuration_revision,configuration_fingerprint,cutoff_sequence) VALUES($1,$2,'configuration_change',1,repeat('a',64),0)`, uuid.NewString(), f.account)
	f.wantTopics(t, f.peer, signals, m.Processing)
	f.wantTopics(t, f.manager, signals, m.Configuration, m.Processing)
	f.wantTopics(t, f.outsider, signals)
}
