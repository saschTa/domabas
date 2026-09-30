ALTER TABLE document_uploads DROP CONSTRAINT document_uploads_media_type_check;
ALTER TABLE document_uploads ADD CONSTRAINT document_uploads_media_type_check CHECK(media_type IN ('image/png','image/jpeg','application/pdf','message/rfc822'));
ALTER TABLE document_files DROP CONSTRAINT document_files_media_type_check;
ALTER TABLE document_files ADD CONSTRAINT document_files_media_type_check CHECK(media_type IN ('image/png','image/jpeg','application/pdf','message/rfc822'));
ALTER TABLE documents ADD COLUMN machine_extraction_method text CHECK(machine_extraction_method IN ('ocr','mime'));
ALTER TABLE documents ADD COLUMN machine_extraction_engine text;
ALTER TABLE documents ADD COLUMN machine_extraction_engine_version text;
ALTER TABLE document_processing ADD COLUMN initiated_by_user_id uuid;
ALTER TABLE document_processing ADD COLUMN parent_batch_id uuid;
ALTER TABLE document_processing ADD COLUMN extraction_method text CHECK(extraction_method IN ('ocr','mime'));
ALTER TABLE document_processing ADD COLUMN extraction_engine text;
ALTER TABLE document_processing ADD COLUMN extraction_engine_version text;
ALTER TABLE document_processing_jobs ADD COLUMN initiated_by_user_id uuid;
ALTER TABLE document_processing_jobs ADD COLUMN parent_batch_id uuid;
ALTER TABLE document_processing_jobs ADD COLUMN extraction_method text CHECK(extraction_method IN ('ocr','mime'));
ALTER TABLE document_processing_jobs ADD COLUMN extraction_engine text;
ALTER TABLE document_processing_jobs ADD COLUMN extraction_engine_version text;
CREATE INDEX document_processing_jobs_initiator_idx ON document_processing_jobs(initiated_by_user_id,created_at DESC,id DESC) WHERE parent_batch_id IS NULL;
CREATE INDEX document_processing_jobs_finished_initiator_idx ON document_processing_jobs(initiated_by_user_id,finished_at DESC,id DESC) WHERE parent_batch_id IS NULL;
UPDATE documents SET machine_extraction_method='ocr',machine_extraction_engine='tesseract',machine_extraction_engine_version='5.5.3' WHERE machine_extraction_fingerprint IS NOT NULL;
UPDATE document_processing_jobs SET extraction_method='ocr',extraction_engine=configuration->>'Engine',extraction_engine_version=configuration->>'EngineVersion' WHERE requires_extraction AND reason<>'legacy' AND stage IN ('embedding','finalizing','complete');
UPDATE document_processing p SET extraction_method=j.extraction_method,extraction_engine=j.extraction_engine,extraction_engine_version=j.extraction_engine_version FROM document_processing_jobs j WHERE j.account_id=p.account_id AND j.document_id=p.document_id AND j.generation=p.generation;
CREATE OR REPLACE FUNCTION document_processing_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  UPDATE document_processing_jobs SET status='cancelled',failure_code='document_deleted',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND generation=OLD.generation AND status IN ('queued','running');
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND OLD.generation<>NEW.generation THEN
  UPDATE document_processing_jobs SET status='superseded',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND generation=OLD.generation AND status IN ('queued','running');
 END IF;
 INSERT INTO document_processing_jobs(account_id,document_id,generation,generation_sequence,requires_extraction,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,started_at,finished_at,updated_at,initiated_by_user_id,parent_batch_id,extraction_method,extraction_engine,extraction_engine_version)
 VALUES(NEW.account_id,NEW.document_id,NEW.generation,NEW.generation_sequence,NEW.requires_extraction,NEW.reason,NEW.configuration_revision,NEW.configuration->>'Fingerprint',NEW.configuration,CASE NEW.state WHEN 'processing' THEN 'running' WHEN 'ready' THEN 'succeeded' ELSE NEW.state END,NEW.stage,CASE WHEN (SELECT ocr_manual_text FROM documents WHERE id=NEW.document_id) IS NULL THEN 'machine' ELSE 'manual' END,NEW.failure_code,CASE WHEN NEW.state='processing' AND NEW.reason<>'legacy' THEN clock_timestamp() END,CASE WHEN NEW.state IN ('ready','failed') THEN clock_timestamp() END,NEW.updated_at,NEW.initiated_by_user_id,NEW.parent_batch_id,NEW.extraction_method,NEW.extraction_engine,NEW.extraction_engine_version)
 ON CONFLICT(account_id,document_id,generation) DO UPDATE SET status=EXCLUDED.status,stage=CASE WHEN EXCLUDED.status='failed' THEN document_processing_jobs.stage ELSE EXCLUDED.stage END,failure_code=EXCLUDED.failure_code,started_at=COALESCE(document_processing_jobs.started_at,EXCLUDED.started_at),finished_at=COALESCE(document_processing_jobs.finished_at,EXCLUDED.finished_at),updated_at=EXCLUDED.updated_at,extraction_method=COALESCE(document_processing_jobs.extraction_method,EXCLUDED.extraction_method),extraction_engine=COALESCE(document_processing_jobs.extraction_engine,EXCLUDED.extraction_engine),extraction_engine_version=COALESCE(document_processing_jobs.extraction_engine_version,EXCLUDED.extraction_engine_version) WHERE document_processing_jobs.status IN ('queued','running');
 RETURN NEW;
END
$$;
CREATE TABLE email_providers (
 id uuid PRIMARY KEY, account_id uuid NOT NULL, owner_id uuid NOT NULL,
 label text NOT NULL CHECK(char_length(label) BETWEEN 1 AND 100),
 host text NOT NULL CHECK(octet_length(host) BETWEEN 1 AND 253),
 port integer NOT NULL CHECK(port BETWEEN 1 AND 65535),
 mailbox text NOT NULL CHECK(octet_length(mailbox) BETWEEN 1 AND 255),
 enabled boolean NOT NULL DEFAULT false,
 interval_minutes integer NOT NULL CHECK(interval_minutes BETWEEN 5 AND 1440),
 max_age_days integer NOT NULL CHECK(max_age_days BETWEEN 1 AND 3650),
 page_size integer NOT NULL CHECK(page_size BETWEEN 1 AND 100),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 source_generation bigint NOT NULL DEFAULT 1 CHECK(source_generation>0),
 credential_version bigint NOT NULL DEFAULT 1 CHECK(credential_version>0),
 consent_revision bigint, credential_key_id text, credential_ciphertext bytea,
 deleted_at timestamptz, next_poll_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 last_served_at timestamptz NOT NULL DEFAULT '-infinity', last_run_id uuid,
 last_failure_code text, retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count>=0),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK((credential_key_id IS NULL)=(credential_ciphertext IS NULL)),
 CHECK(credential_key_id IS NULL OR credential_key_id ~ '^[A-Za-z0-9_-]{1,32}$'),
 CHECK(credential_ciphertext IS NULL OR octet_length(credential_ciphertext) BETWEEN 35 AND 8192),
 CHECK(deleted_at IS NULL OR credential_ciphertext IS NULL)
);
CREATE INDEX email_providers_owner_idx ON email_providers(owner_id,account_id,created_at DESC,id DESC) WHERE deleted_at IS NULL;
CREATE INDEX email_providers_due_idx ON email_providers(next_poll_at,last_served_at,id) WHERE enabled AND deleted_at IS NULL;
CREATE TABLE email_runs (
 id uuid PRIMARY KEY,provider_id uuid NOT NULL,account_id uuid NOT NULL,owner_id uuid NOT NULL,
 provider_revision bigint NOT NULL CHECK(provider_revision>0),source_generation bigint NOT NULL CHECK(source_generation>0),mailbox_generation bigint NOT NULL DEFAULT 0 CHECK(mailbox_generation>=0),
 trigger text NOT NULL CHECK(trigger IN ('manual','scheduled','continuation')),
 request_id uuid,
 status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','succeeded','partial','failed','cancelled','superseded')),
 failure_code text,stage text NOT NULL DEFAULT 'queued' CHECK(stage IN ('queued','discovering','fetching','importing','complete')),
 messages_discovered bigint NOT NULL DEFAULT 0 CHECK(messages_discovered>=0),messages_accepted bigint NOT NULL DEFAULT 0 CHECK(messages_accepted>=0),messages_reused bigint NOT NULL DEFAULT 0 CHECK(messages_reused>=0),messages_skipped bigint NOT NULL DEFAULT 0 CHECK(messages_skipped>=0),messages_failed bigint NOT NULL DEFAULT 0 CHECK(messages_failed>=0),messages_with_content_failures bigint NOT NULL DEFAULT 0 CHECK(messages_with_content_failures>=0),
 attachments_accepted bigint NOT NULL DEFAULT 0 CHECK(attachments_accepted>=0),attachments_reused bigint NOT NULL DEFAULT 0 CHECK(attachments_reused>=0),attachments_skipped bigint NOT NULL DEFAULT 0 CHECK(attachments_skipped>=0),attachments_failed bigint NOT NULL DEFAULT 0 CHECK(attachments_failed>=0),
 has_more boolean NOT NULL DEFAULT false,
 page_index integer NOT NULL DEFAULT -1 CHECK(page_index BETWEEN -1 AND 3),activity_id text,activity_attempt integer NOT NULL DEFAULT 0 CHECK(activity_attempt>=0),attempt_token uuid,attempt_deadline timestamptz,workflow_run_id text,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,started_at timestamptz,finished_at timestamptz,
 UNIQUE(owner_id,provider_id,request_id),
 CHECK((attempt_token IS NULL)=(attempt_deadline IS NULL))
);
CREATE UNIQUE INDEX email_runs_active_idx ON email_runs(provider_id) WHERE status IN ('queued','running');
CREATE INDEX email_runs_owner_idx ON email_runs(owner_id,account_id,created_at DESC,id DESC);
CREATE INDEX email_runs_provider_idx ON email_runs(provider_id,created_at DESC,id DESC);
CREATE INDEX email_runs_finished_idx ON email_runs(owner_id,finished_at DESC,id DESC);
CREATE TABLE email_outbox (
 run_id uuid PRIMARY KEY,available_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 lease_token uuid,lease_expires_at timestamptz,acknowledged_at timestamptz,
 CHECK((lease_token IS NULL)=(lease_expires_at IS NULL))
);
CREATE INDEX email_outbox_due_idx ON email_outbox(available_at,run_id) WHERE acknowledged_at IS NULL;
CREATE TABLE email_executions (
 run_id uuid PRIMARY KEY,workflow_id text NOT NULL UNIQUE,task_queue text NOT NULL,workflow_run_id text,
 first_attempt_at timestamptz NOT NULL,start_window_end timestamptz NOT NULL,latest_permit_end timestamptz,
 next_check_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,closed_at timestamptz,terminal_fenced_at timestamptz,
 CHECK(start_window_end=first_attempt_at+interval '23 hours 59 minutes')
);
CREATE INDEX email_executions_pending_idx ON email_executions(next_check_at) WHERE closed_at IS NULL;
CREATE TABLE email_admission (id boolean PRIMARY KEY DEFAULT true CHECK(id),run_id uuid);
INSERT INTO email_admission(id) VALUES(true);
CREATE TABLE email_mailboxes (
 provider_id uuid NOT NULL,source_generation bigint NOT NULL CHECK(source_generation>0),
 mailbox_generation bigint NOT NULL DEFAULT 1 CHECK(mailbox_generation>0),uid_validity bigint NOT NULL CHECK(uid_validity BETWEEN 1 AND 4294967295),
 live_upper_uid bigint CHECK(live_upper_uid BETWEEN 0 AND 4294967295),
 live_next_uid bigint NOT NULL DEFAULT 1 CHECK(live_next_uid BETWEEN 1 AND 4294967296),
 backfill_next_uid bigint,backfill_upper_uid bigint,
 max_age_days integer NOT NULL CHECK(max_age_days BETWEEN 1 AND 3650),
 discovery_backfill_next boolean NOT NULL DEFAULT false,retry_next boolean NOT NULL DEFAULT false,
 PRIMARY KEY(provider_id,source_generation),
 CHECK((backfill_next_uid IS NULL)=(backfill_upper_uid IS NULL)),
 CHECK(backfill_next_uid IS NULL OR backfill_next_uid BETWEEN 1 AND 4294967296),CHECK(backfill_upper_uid IS NULL OR backfill_upper_uid BETWEEN 0 AND 4294967295)
);
CREATE TABLE email_messages (
 id uuid PRIMARY KEY,provider_id uuid NOT NULL,account_id uuid NOT NULL,owner_id uuid NOT NULL,
 source_generation bigint NOT NULL,mailbox_generation bigint NOT NULL,uid bigint NOT NULL CHECK(uid BETWEEN 1 AND 4294967295),
 run_id uuid NOT NULL,provider_revision bigint NOT NULL,attempt_token uuid,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','accepted','reused','skipped','failed','deleted')),
 failure_code text,parent_document_id uuid,internal_date timestamptz,
 inspection_state text NOT NULL DEFAULT 'pending' CHECK(inspection_state IN ('pending','complete','failed')),
 content_failure boolean NOT NULL DEFAULT false,pending_parts boolean NOT NULL DEFAULT false,
 retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count>=0),next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,last_attempt_at timestamptz NOT NULL DEFAULT '-infinity',last_counted_run_id uuid,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(provider_id,source_generation,mailbox_generation,uid)
);
CREATE INDEX email_messages_pending_idx ON email_messages(provider_id,source_generation,mailbox_generation,next_attempt_at,last_attempt_at,id) WHERE state='pending' OR inspection_state='pending' OR pending_parts;
CREATE INDEX email_messages_parent_idx ON email_messages(account_id,parent_document_id);
CREATE TABLE email_parts (
 id uuid PRIMARY KEY,message_id uuid NOT NULL,account_id uuid NOT NULL,path text NOT NULL CHECK(path ~ '^(0|[1-9][0-9]*)(\.[1-9][0-9]*)*$' AND octet_length(path)<=128),
 filename text NOT NULL DEFAULT '' CHECK(octet_length(filename)<=1024),media_type text NOT NULL DEFAULT '',
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','accepted','reused','skipped','failed','deleted')),
 failure_code text,document_id uuid,reservation_id uuid,attempt_token uuid,
 last_counted_run_id uuid,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(message_id,path)
);
CREATE INDEX email_parts_document_idx ON email_parts(account_id,document_id);
CREATE INDEX email_parts_message_idx ON email_parts(message_id,path);
CREATE TABLE email_test_limits (
 owner_id uuid PRIMARY KEY,lease_token uuid NOT NULL,lease_until timestamptz NOT NULL,next_allowed_at timestamptz NOT NULL
);
