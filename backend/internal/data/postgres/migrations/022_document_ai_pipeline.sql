ALTER TABLE document_processing ADD COLUMN split_pipeline boolean NOT NULL DEFAULT false;
ALTER TABLE document_processing ALTER COLUMN split_pipeline SET DEFAULT true;
ALTER TABLE document_processing ADD COLUMN invoice_failure_code text CHECK(invoice_failure_code IS NULL OR invoice_failure_code='invalid_invoice');
ALTER TABLE document_processing_executions ADD COLUMN split_pipeline boolean NOT NULL DEFAULT false;
ALTER TABLE document_processing_jobs ADD COLUMN split_pipeline boolean NOT NULL DEFAULT false;
ALTER TABLE document_processing_configuration ADD COLUMN ai_reschedule_revision bigint;
ALTER TABLE document_processing_configuration ADD COLUMN ai_reschedule_cutoff bigint;
ALTER TABLE document_processing_configuration ADD COLUMN ai_reschedule_cursor bigint NOT NULL DEFAULT 0;
CREATE TABLE document_ai_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 account_id uuid NOT NULL,document_id uuid NOT NULL,generation bigint NOT NULL CHECK(generation>0),
 attempt bigint NOT NULL CHECK(attempt>0),ocr_revision bigint NOT NULL CHECK(ocr_revision>=0),
 reason text NOT NULL CHECK(reason IN ('upload','retry','ocr_correction','reindex','legacy','configuration_change')),
 configuration_revision bigint NOT NULL,configuration_fingerprint text NOT NULL,configuration jsonb NOT NULL,
 status text NOT NULL CHECK(status IN ('queued','running','succeeded','failed','skipped','superseded','cancelled')),
 stage text NOT NULL CHECK(stage IN ('queued','invoicing','enriching','complete','failed')),
 text_source text NOT NULL CHECK(text_source IN ('machine','manual')),invoice_done boolean NOT NULL DEFAULT false,
 failure_code text,initiated_by_user_id uuid,parent_batch_id uuid,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),started_at timestamptz,finished_at timestamptz,
 workflow_id text NOT NULL DEFAULT '',task_queue text NOT NULL DEFAULT '',run_id text NOT NULL DEFAULT '',
 admitted_at timestamptz,delivery_deadline timestamptz,first_permit_at timestamptz,start_retry_until timestamptz,latest_permit_end timestamptz,
 lease_token uuid,lease_expires_at timestamptz,next_check_at timestamptz NOT NULL DEFAULT clock_timestamp(),closed_at timestamptz,
 UNIQUE(account_id,document_id,attempt)
);
CREATE INDEX document_ai_jobs_page_idx ON document_ai_jobs(account_id,created_at DESC,id DESC);
CREATE INDEX document_ai_jobs_current_idx ON document_ai_jobs(account_id,document_id,attempt DESC);
CREATE INDEX document_ai_jobs_open_idx ON document_ai_jobs(next_check_at) WHERE admitted_at IS NOT NULL AND closed_at IS NULL;
CREATE INDEX document_ai_jobs_waiting_idx ON document_ai_jobs(created_at,id) WHERE status='queued' AND admitted_at IS NULL;
CREATE FUNCTION document_ai_publish() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  UPDATE document_ai_jobs SET status='cancelled',failure_code='document_deleted',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND status IN ('queued','running');
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND (OLD.generation<>NEW.generation OR OLD.ocr_revision<>NEW.ocr_revision) THEN
  UPDATE document_ai_jobs SET status='superseded',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=NEW.account_id AND document_id=NEW.document_id AND status IN ('queued','running');
 END IF;
 UPDATE document_processing_jobs SET split_pipeline=NEW.split_pipeline WHERE account_id=NEW.account_id AND document_id=NEW.document_id AND generation=NEW.generation;
 IF NEW.split_pipeline AND NEW.state='ready' AND (TG_OP='INSERT' OR OLD.state<>'ready' OR OLD.generation<>NEW.generation) THEN
  INSERT INTO document_ai_jobs(account_id,document_id,generation,attempt,ocr_revision,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,initiated_by_user_id,parent_batch_id,finished_at)
  SELECT NEW.account_id,NEW.document_id,NEW.generation,COALESCE((SELECT max(attempt)+1 FROM document_ai_jobs WHERE account_id=NEW.account_id AND document_id=NEW.document_id),1),NEW.ocr_revision,NEW.reason,c.revision,c.configuration->>'Fingerprint',c.configuration,
   CASE WHEN COALESCE((c.configuration->'LLM'->>'Enabled')::boolean,false) OR COALESCE((c.configuration->'LLM'->>'InvoiceEnabled')::boolean,(c.configuration->'LLM'->>'Enabled')::boolean,false) OR NEW.invoice_xml IS NOT NULL OR NEW.invoice_failure_code IS NOT NULL THEN 'queued' ELSE 'skipped' END,
   CASE WHEN COALESCE((c.configuration->'LLM'->>'Enabled')::boolean,false) OR COALESCE((c.configuration->'LLM'->>'InvoiceEnabled')::boolean,(c.configuration->'LLM'->>'Enabled')::boolean,false) OR NEW.invoice_xml IS NOT NULL OR NEW.invoice_failure_code IS NOT NULL THEN 'queued' ELSE 'complete' END,
   CASE WHEN d.ocr_manual_text IS NULL THEN 'machine' ELSE 'manual' END,NEW.initiated_by_user_id,NEW.parent_batch_id,
   CASE WHEN NOT (COALESCE((c.configuration->'LLM'->>'Enabled')::boolean,false) OR COALESCE((c.configuration->'LLM'->>'InvoiceEnabled')::boolean,(c.configuration->'LLM'->>'Enabled')::boolean,false) OR NEW.invoice_xml IS NOT NULL OR NEW.invoice_failure_code IS NOT NULL) THEN clock_timestamp() END
  FROM documents d CROSS JOIN document_processing_configuration c WHERE c.id=true AND d.account_id=NEW.account_id AND d.id=NEW.document_id;
 END IF;
 RETURN NEW;
END
$$;
CREATE TRIGGER z_document_ai_publish AFTER INSERT OR UPDATE OR DELETE ON document_processing FOR EACH ROW EXECUTE FUNCTION document_ai_publish();
CREATE VIEW document_pipeline_jobs AS
 SELECT id,account_id,document_id,generation,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,created_at,updated_at,started_at,finished_at,initiated_by_user_id,parent_batch_id,extraction_method,extraction_engine,extraction_engine_version,'ingestion'::text pipeline,NULL::bigint attempt,CASE WHEN split_pipeline THEN 2 ELSE 1 END pipeline_version FROM document_processing_jobs
 UNION ALL
 SELECT id,account_id,document_id,generation,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,created_at,updated_at,started_at,finished_at,initiated_by_user_id,parent_batch_id,NULL::text,NULL::text,NULL::text,'ai',attempt,1 FROM document_ai_jobs;
CREATE FUNCTION realtime_document_ai_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM realtime_notify(TG_TABLE_SCHEMA,'documents',NEW.account_id,NULL);
 PERFORM realtime_notify(TG_TABLE_SCHEMA,'document_job',NEW.account_id,CASE WHEN NEW.parent_batch_id IS NULL THEN NEW.initiated_by_user_id END);
 RETURN NULL;
END
$$;
CREATE TRIGGER realtime_document_ai_changed AFTER INSERT OR UPDATE ON document_ai_jobs FOR EACH ROW EXECUTE FUNCTION realtime_document_ai_changed();
DO $$ BEGIN
 EXECUTE format('ALTER FUNCTION %I.document_ai_publish() SET search_path = %I, pg_catalog, pg_temp',current_schema(),current_schema());
 EXECUTE format('ALTER FUNCTION %I.realtime_document_ai_changed() SET search_path = %I, pg_catalog, pg_temp',current_schema(),current_schema());
END $$;
