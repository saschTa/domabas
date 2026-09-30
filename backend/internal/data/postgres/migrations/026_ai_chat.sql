CREATE TABLE chat_admission(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton));
INSERT INTO chat_admission DEFAULT VALUES;
CREATE TABLE chat_credentials(id uuid PRIMARY KEY, encrypted_key bytea NOT NULL);
CREATE TABLE chat_configuration(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 enabled boolean NOT NULL DEFAULT true, provider text NOT NULL DEFAULT 'ollama' CHECK(provider IN ('ollama','openai')),
 model text NOT NULL DEFAULT 'gemma3:4b',base_url text NOT NULL DEFAULT '',credential_id uuid REFERENCES chat_credentials(id),
 internal_runtime boolean NOT NULL DEFAULT true,updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO chat_configuration DEFAULT VALUES;
CREATE TABLE chat_conversations(
 id uuid PRIMARY KEY, account_id uuid NOT NULL REFERENCES accounts(id),owner_id uuid NOT NULL REFERENCES users(id),
 request_id uuid NOT NULL,title text NOT NULL DEFAULT 'New chat',next_sequence bigint NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),deleted_at timestamptz,
 UNIQUE(account_id,owner_id,request_id),UNIQUE(id,account_id,owner_id)
);
CREATE INDEX chat_conversation_page ON chat_conversations(account_id,owner_id,created_at DESC,id DESC) WHERE deleted_at IS NULL;
CREATE TABLE chat_turns(
 id uuid PRIMARY KEY,conversation_id uuid NOT NULL,account_id uuid NOT NULL,owner_id uuid NOT NULL,request_id uuid NOT NULL,
 credential_revision bigint NOT NULL,content_hash bytea NOT NULL,
 status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','completed','failed','cancelled')),
 stage text NOT NULL DEFAULT 'queued',failure_code text NOT NULL DEFAULT '',
 configuration_revision bigint NOT NULL,provider text NOT NULL,model text NOT NULL,base_url text NOT NULL,
 credential_id uuid REFERENCES chat_credentials(id),internal_runtime boolean NOT NULL,
 workflow_id text NOT NULL,task_queue text NOT NULL,run_id text NOT NULL DEFAULT '',
 admitted_at timestamptz,first_start_at timestamptz,delivery_token uuid,delivery_expires_at timestamptz,
 next_check_at timestamptz NOT NULL DEFAULT clock_timestamp(),execution_closed boolean NOT NULL DEFAULT false,
 execution_token uuid,execution_expires_at timestamptz,execution_drained_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),finished_at timestamptz,
 FOREIGN KEY(conversation_id,account_id,owner_id) REFERENCES chat_conversations(id,account_id,owner_id),
 UNIQUE(conversation_id,request_id),UNIQUE(id,conversation_id)
);
CREATE UNIQUE INDEX chat_turn_active ON chat_turns(conversation_id) WHERE status IN ('queued','running');
CREATE INDEX chat_turn_dispatch ON chat_turns(next_check_at,created_at) WHERE NOT execution_closed;
CREATE TABLE chat_messages(
 id uuid PRIMARY KEY,conversation_id uuid NOT NULL REFERENCES chat_conversations(id),turn_id uuid NOT NULL,
 sequence bigint NOT NULL,role text NOT NULL CHECK(role IN ('user','assistant')),content text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(turn_id,conversation_id) REFERENCES chat_turns(id,conversation_id),UNIQUE(conversation_id,sequence),UNIQUE(turn_id,role)
);
CREATE TABLE chat_tool_results(
 turn_id uuid NOT NULL REFERENCES chat_turns(id),ordinal integer NOT NULL CHECK(ordinal BETWEEN 0 AND 7),
 kind text NOT NULL CHECK(kind IN ('search_documents','read_document')),query text NOT NULL DEFAULT '',document_id uuid,
 text_offset integer NOT NULL DEFAULT 0 CHECK(text_offset>=0),tool_call_id text NOT NULL DEFAULT '',result_text text NOT NULL,
 PRIMARY KEY(turn_id,ordinal)
);
CREATE TABLE chat_sources(
 turn_id uuid NOT NULL,ordinal integer NOT NULL,document_id uuid NOT NULL,title text NOT NULL,excerpt text NOT NULL DEFAULT '',
 PRIMARY KEY(turn_id,ordinal,document_id),FOREIGN KEY(turn_id,ordinal) REFERENCES chat_tool_results(turn_id,ordinal)
);
