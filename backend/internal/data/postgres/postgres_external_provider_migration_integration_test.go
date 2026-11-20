//go:build integration

package postgres

import (
	"testing"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func TestExternalProviderMigrationRetiresLocalWorkAndKeepsExternalSnapshots(t *testing.T) {
	ctx := t.Context()
	for _, external := range []bool{false, true} {
		name := "local configuration"
		if external {
			name = "external configuration"
		}
		t.Run(name, func(t *testing.T) {
			source := migrationSource(t, testdb.New(t))
			if err := source.migrate(ctx, migrationsThrough(t, "043")); err != nil {
				t.Fatal(err)
			}
			account, user, credential := uuid.New(), uuid.New(), uuid.New()
			migrationSQL(t, source, "INSERT INTO accounts(id,name) VALUES($1,'Migration fixture')", account)
			migrationSQL(t, source, "WITH u AS (INSERT INTO users(id,email,password_hash,personal_account_id) VALUES($1,'migration@example.test','unused',$2) RETURNING id) INSERT INTO memberships(account_id,user_id,role,is_owner) SELECT $2,id,'admin',true FROM u", user, account)
			migrationSQL(t, source, "INSERT INTO chat_credentials(id,encrypted_key) VALUES($1,'unchanged')", credential)
			if external {
				migrationSQL(t, source, "UPDATE chat_configuration SET revision=7,enabled=true,provider='openai',model='retained-model',base_url='https://provider.test/v1',credential_id=$1,internal_runtime=false", credential)
			}
			for _, provider := range []string{"ollama", "openai"} {
				id := uuid.New()
				migrationSQL(t, source, "INSERT INTO chat_conversations(id,account_id,owner_id,request_id) VALUES($1,$2,$3,$1)", id, account, user)
				migrationSQL(t, source, `INSERT INTO chat_turns(id,conversation_id,account_id,owner_id,request_id,credential_revision,content_hash,configuration_revision,provider,model,base_url,credential_id,internal_runtime,workflow_id,task_queue,status)
VALUES($1,$1,$2,$3,$1,1,'',1,$4,'original-model',CASE WHEN $4='openai' THEN 'https://provider.test/v1' ELSE '' END,CASE WHEN $4='openai' THEN $5::uuid END,$4='ollama',$4,'fixture','running')`, id, account, user, provider, credential)
				migrationSQL(t, source, "INSERT INTO scheduler_requests(workflow_id,pipeline,state) VALUES($1,'chat','active')", provider)
				migrationSQL(t, source, "INSERT INTO native_executions(workflow_id) VALUES($1)", provider)
				migrationSQL(t, source, "INSERT INTO scheduler_step_permits(workflow_id,resource_id,scope,token) VALUES($1,'stage:llm','model',$2)", provider, uuid.New())
				migrationSQL(t, source, `INSERT INTO document_ai_jobs(account_id,document_id,generation,attempt,ocr_revision,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,lease_token,lease_expires_at)
VALUES($1,$2,1,1,1,'upload',1,'retained',jsonb_build_object('LLM',jsonb_build_object('Enabled',true,'Provider',$3::text,'Model','accepted-model','BaseURL',CASE WHEN $3='openai' THEN 'https://provider.test/v1' ELSE '' END)),'running','invoicing','manual',$2,clock_timestamp()+interval '10 minutes')`, account, id, provider)

			}
			migrationSQL(t, source, "UPDATE scheduler_resources SET concurrency_limit=3 WHERE id='ollama'")
			migrationSQL(t, source, "INSERT INTO scheduler_requests(workflow_id,pipeline,state) VALUES('embed','document_ingestion','active')")
			migrationSQL(t, source, "INSERT INTO scheduler_job_providers(workflow_id,resource_id) VALUES('embed','ollama')")
			migrationSQL(t, source, "INSERT INTO scheduler_step_permits(workflow_id,resource_id,scope,token) VALUES('embed','ollama','model',$1)", uuid.New())
			for range 2 {
				if err := source.Migrate(ctx); err != nil {
					t.Fatal(err)
				}
				var enrichmentOK bool
				err := source.pool.QueryRow(ctx, `SELECT count(*)=2 AND bool_and(CASE scheduler_provider
WHEN 'ollama' THEN status='failed' AND stage='failed' AND closed_at IS NOT NULL AND lease_token IS NULL AND failure_code='configuration_unavailable'
WHEN 'openai' THEN status='running' AND stage='invoicing' AND closed_at IS NULL AND lease_token IS NOT NULL AND configuration->'LLM'->>'BaseURL'='https://provider.test/v1'
ELSE false END) FROM document_ai_jobs`).Scan(&enrichmentOK)
				if err != nil || !enrichmentOK {
					t.Fatalf("retained document enrichment snapshots: %t, %v", enrichmentOK, err)
				}

				var configurationOK, nativeClosed, externalRetained, capacityRetained bool
				err = source.pool.QueryRow(ctx, `SELECT
       (SELECT provider='openai' AND CASE WHEN $1 THEN enabled AND revision=7 AND credential_id=$2 AND model='retained-model' AND base_url='https://provider.test/v1' ELSE NOT enabled AND credential_id IS NULL AND model='' AND base_url='' END FROM chat_configuration),
       EXISTS(SELECT 1 FROM chat_turns t JOIN scheduler_requests q USING(workflow_id) JOIN native_executions n USING(workflow_id) WHERE t.provider='ollama' AND t.status='failed' AND t.failure_code='configuration_unavailable' AND t.execution_closed AND q.state='released' AND n.outcome='failed' AND NOT EXISTS (SELECT 1 FROM scheduler_step_permits p WHERE p.workflow_id=t.workflow_id)),
       EXISTS(SELECT 1 FROM chat_turns t JOIN scheduler_requests q USING(workflow_id) JOIN scheduler_step_permits p USING(workflow_id) WHERE t.provider='openai' AND t.status='running' AND NOT t.execution_closed AND q.state='active' AND t.credential_id=$2 AND t.model='original-model'),
       EXISTS(SELECT 1 FROM scheduler_job_providers j JOIN scheduler_step_permits p USING(workflow_id,resource_id) JOIN scheduler_resources r ON r.id=j.resource_id WHERE j.workflow_id='embed' AND r.id='embedding-runtime' AND r.concurrency_limit=3)`, external, credential).Scan(&configurationOK, &nativeClosed, &externalRetained, &capacityRetained)
				if err != nil || !configurationOK || !nativeClosed || !externalRetained || !capacityRetained {
					t.Fatalf("migration configuration=%t closed=%t external=%t capacity=%t: %v", configurationOK, nativeClosed, externalRetained, capacityRetained, err)
				}
			}
		})
	}
}
