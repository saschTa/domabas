CREATE SEQUENCE document_processing_event_seq;
ALTER TABLE documents ADD COLUMN accepted_sequence bigint;
WITH numbered AS (SELECT id,row_number() OVER(ORDER BY created_at,id) n FROM documents)
UPDATE documents d SET accepted_sequence=n.n FROM numbered n WHERE d.id=n.id;
SELECT setval('document_processing_event_seq',COALESCE((SELECT max(accepted_sequence) FROM documents),0)+1,false);
ALTER TABLE documents ALTER COLUMN accepted_sequence SET NOT NULL;
ALTER TABLE documents ALTER COLUMN accepted_sequence SET DEFAULT nextval('document_processing_event_seq');
CREATE INDEX documents_accepted_sequence_idx ON documents(accepted_sequence,id);
ALTER TABLE documents ADD COLUMN machine_extraction_fingerprint text CHECK(machine_extraction_fingerprint ~ '^[a-f0-9]{64}$');
ALTER TABLE documents ADD COLUMN machine_extraction_sequence bigint;
ALTER TABLE documents ADD COLUMN machine_extracted_at timestamptz;
ALTER TABLE document_processing ALTER COLUMN delivery_deadline DROP NOT NULL;
ALTER TABLE document_outbox ALTER COLUMN delivery_deadline DROP NOT NULL;
ALTER TABLE document_processing ADD COLUMN generation_sequence bigint NOT NULL DEFAULT nextval('document_processing_event_seq');
ALTER TABLE document_processing ADD COLUMN reason text NOT NULL DEFAULT 'upload' CHECK(reason IN ('upload','retry','ocr_correction','reindex','legacy'));
ALTER TABLE document_processing ADD COLUMN requires_extraction boolean NOT NULL DEFAULT true;
ALTER TABLE document_chunks DROP CONSTRAINT document_chunks_model_digest_check;
ALTER TABLE document_chunks ADD CONSTRAINT document_chunks_model_digest_check CHECK(model_digest ~ '^[a-f0-9]{64}$');

CREATE FUNCTION document_pipeline_fingerprint(c jsonb) RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT encode(sha256(convert_to('['||string_agg(replace(replace(replace(replace(replace(to_json(v)::text,'<','\u003c'),'>','\u003e'),'&','\u0026'),chr(8232),'\u2028'),chr(8233),'\u2029'),',' ORDER BY position)||']','UTF8')),'hex') FROM (
 SELECT v,position FROM unnest(ARRAY['1',c->>'Language',c->>'Segmentation',c->>'Engine',c->>'EngineVersion',c->>'EmbeddingModel',c->>'EmbeddingDigest',c->>'Dimensions',c->>'ExtractionRevision',c->>'ChunkingRevision',c->>'EmbeddingInputRevision',c->>'IndexingRevision']) WITH ORDINALITY t(v,position)
 UNION ALL
 SELECT CASE WHEN part=0 THEN w->>'Name' ELSE w->>'SHA256' END,12+2*(row_number() OVER(ORDER BY (w->>'Name') COLLATE "C",part))-part FROM jsonb_array_elements(c->'Weights') w CROSS JOIN generate_series(0,1) part
 ) fields
$$;
CREATE FUNCTION document_legacy_snapshot(c jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT value||jsonb_build_object('Fingerprint',document_pipeline_fingerprint(value)) FROM (SELECT c||jsonb_build_object('ManifestRevision',1,'ExtractionRevision','tesseract-pdf-image-v1','ChunkingRevision','ocr-rune-chunks-v1','EmbeddingInputRevision','nomic-search-prefix-v1','IndexingRevision','normalized-cosine-v1') value) s
$$;
UPDATE document_processing SET configuration=document_legacy_snapshot(configuration),reason='legacy';
UPDATE documents d SET machine_extraction_fingerprint=p.configuration->>'Fingerprint',machine_extraction_sequence=p.generation_sequence,machine_extracted_at=p.updated_at FROM document_processing p WHERE p.document_id=d.id AND p.account_id=d.account_id AND d.ocr_machine_text IS NOT NULL AND d.ocr_manual_text IS NULL AND p.stage IN ('embedding','finalizing','complete');
ALTER TABLE document_processing_configuration ADD COLUMN configuration jsonb;
ALTER TABLE document_processing_configuration ADD COLUMN fingerprint text;
ALTER TABLE document_processing_configuration ADD COLUMN manifest_revision bigint;
ALTER TABLE document_processing_configuration ADD COLUMN manifest_fingerprint text;
ALTER TABLE document_processing_configuration ADD COLUMN automatic_batch_id uuid;
ALTER TABLE document_processing_configuration ADD COLUMN adopted boolean NOT NULL DEFAULT false;
CREATE TABLE document_processing_configurations(revision bigint PRIMARY KEY,configuration jsonb NOT NULL,fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE document_processing_jobs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),account_id uuid NOT NULL,document_id uuid NOT NULL,generation bigint NOT NULL,
 generation_sequence bigint NOT NULL,requires_extraction boolean NOT NULL,reason text NOT NULL,
 configuration_revision bigint NOT NULL,configuration_fingerprint text NOT NULL,configuration jsonb NOT NULL,
 status text NOT NULL CHECK(status IN ('queued','running','succeeded','failed','superseded','cancelled')),
 stage text NOT NULL,text_source text NOT NULL CHECK(text_source IN ('machine','manual')),
 failure_code text,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),started_at timestamptz,finished_at timestamptz,updated_at timestamptz NOT NULL,
 UNIQUE(account_id,document_id,generation));
CREATE INDEX document_processing_jobs_page_idx ON document_processing_jobs(account_id,created_at DESC,id DESC);
CREATE INDEX document_processing_jobs_document_idx ON document_processing_jobs(account_id,document_id,generation DESC);
INSERT INTO document_processing_jobs(account_id,document_id,generation,generation_sequence,requires_extraction,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,finished_at,updated_at)
SELECT p.account_id,p.document_id,p.generation,p.generation_sequence,p.requires_extraction,'legacy',p.configuration_revision,p.configuration->>'Fingerprint',p.configuration,CASE p.state WHEN 'processing' THEN 'running' WHEN 'ready' THEN 'succeeded' ELSE p.state END,p.stage,CASE WHEN d.ocr_manual_text IS NULL THEN 'machine' ELSE 'manual' END,p.failure_code,CASE WHEN p.state IN ('ready','failed') THEN p.updated_at END,p.updated_at FROM document_processing p JOIN documents d ON d.id=p.document_id;
CREATE FUNCTION document_processing_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  UPDATE document_processing_jobs SET status='cancelled',failure_code='document_deleted',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND generation=OLD.generation AND status IN ('queued','running');
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND OLD.generation<>NEW.generation THEN
  UPDATE document_processing_jobs SET status='superseded',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND generation=OLD.generation AND status IN ('queued','running');
 END IF;
 INSERT INTO document_processing_jobs(account_id,document_id,generation,generation_sequence,requires_extraction,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,started_at,finished_at,updated_at)
 VALUES(NEW.account_id,NEW.document_id,NEW.generation,NEW.generation_sequence,NEW.requires_extraction,NEW.reason,NEW.configuration_revision,NEW.configuration->>'Fingerprint',NEW.configuration,CASE NEW.state WHEN 'processing' THEN 'running' WHEN 'ready' THEN 'succeeded' ELSE NEW.state END,NEW.stage,CASE WHEN (SELECT ocr_manual_text FROM documents WHERE id=NEW.document_id) IS NULL THEN 'machine' ELSE 'manual' END,NEW.failure_code,CASE WHEN NEW.state='processing' THEN clock_timestamp() END,CASE WHEN NEW.state IN ('ready','failed') THEN clock_timestamp() END,NEW.updated_at)
 ON CONFLICT(account_id,document_id,generation) DO UPDATE SET status=EXCLUDED.status,stage=CASE WHEN EXCLUDED.status='failed' THEN document_processing_jobs.stage ELSE EXCLUDED.stage END,failure_code=EXCLUDED.failure_code,started_at=COALESCE(document_processing_jobs.started_at,EXCLUDED.started_at),finished_at=COALESCE(document_processing_jobs.finished_at,EXCLUDED.finished_at),updated_at=EXCLUDED.updated_at WHERE document_processing_jobs.status IN ('queued','running');
 RETURN NEW;
END
$$;
CREATE TRIGGER document_processing_history AFTER INSERT OR UPDATE OR DELETE ON document_processing FOR EACH ROW EXECUTE FUNCTION document_processing_history();
CREATE TABLE document_reindex_batches(
 id uuid PRIMARY KEY,account_id uuid,requester_id uuid,reason text NOT NULL CHECK(reason IN ('manual','configuration_change','adoption')),
 configuration_revision bigint NOT NULL,configuration_fingerprint text NOT NULL,cutoff_sequence bigint NOT NULL,cursor_sequence bigint NOT NULL DEFAULT 0,cursor_id uuid,
 enumeration_complete boolean NOT NULL DEFAULT false,status text NOT NULL DEFAULT 'enumerating' CHECK(status IN ('enumerating','running','succeeded','completed_with_failures','superseded')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),finished_at timestamptz,last_served_at timestamptz,
 discovered bigint NOT NULL DEFAULT 0,waiting bigint NOT NULL DEFAULT 0,running bigint NOT NULL DEFAULT 0,succeeded bigint NOT NULL DEFAULT 0,failed bigint NOT NULL DEFAULT 0,skipped bigint NOT NULL DEFAULT 0,superseded bigint NOT NULL DEFAULT 0);
CREATE UNIQUE INDEX document_reindex_active_manual_idx ON document_reindex_batches(COALESCE(account_id,'00000000-0000-0000-0000-000000000000'::uuid),configuration_revision) WHERE reason='manual' AND status IN ('enumerating','running');
CREATE UNIQUE INDEX document_reindex_automatic_idx ON document_reindex_batches(configuration_revision) WHERE reason IN ('configuration_change','adoption');
CREATE INDEX document_reindex_batches_page_idx ON document_reindex_batches(account_id,created_at DESC,id DESC);
CREATE TABLE document_reindex_items(
 batch_id uuid NOT NULL REFERENCES document_reindex_batches(id) ON DELETE CASCADE,account_id uuid NOT NULL,document_id uuid NOT NULL,
 generation bigint,job_id uuid,next_check_at timestamptz NOT NULL DEFAULT clock_timestamp(),status text NOT NULL DEFAULT 'waiting' CHECK(status IN ('waiting','running','succeeded','failed','skipped','superseded')),outcome_code text,
 PRIMARY KEY(batch_id,document_id));
CREATE INDEX document_reindex_items_waiting_idx ON document_reindex_items(batch_id,status,document_id);
CREATE TABLE document_processing_admission(id boolean PRIMARY KEY DEFAULT true CHECK(id),account_id uuid,document_id uuid,generation bigint,last_class text NOT NULL DEFAULT 'reindex',last_batch_id uuid);
INSERT INTO document_processing_admission(id) VALUES(true);
CREATE TABLE document_processing_executions(
 account_id uuid NOT NULL,document_id uuid NOT NULL,generation bigint NOT NULL,outbox_id uuid,job_id uuid,
 workflow_id text NOT NULL,task_queue text NOT NULL DEFAULT '',run_id text NOT NULL DEFAULT '',admitted_at timestamptz NOT NULL,
 delivery_deadline timestamptz NOT NULL,first_permit_at timestamptz,start_retry_until timestamptz,latest_permit_end timestamptz,
 lease_token uuid,lease_expires_at timestamptz,next_check_at timestamptz NOT NULL DEFAULT clock_timestamp(),closed_at timestamptz,
 execution_timeout_seconds integer NOT NULL DEFAULT 900 CHECK(execution_timeout_seconds=900),legacy boolean NOT NULL DEFAULT false,
 PRIMARY KEY(account_id,document_id,generation));
CREATE INDEX document_processing_executions_open_idx ON document_processing_executions(next_check_at) WHERE closed_at IS NULL;
INSERT INTO document_processing_executions(account_id,document_id,generation,outbox_id,job_id,workflow_id,run_id,admitted_at,delivery_deadline,first_permit_at,start_retry_until,latest_permit_end,legacy)
SELECT p.account_id,p.document_id,p.generation,o.id,j.id,'document-ingestion-v1/'||p.account_id||'/'||p.document_id||'/'||p.generation,p.run_id,COALESCE(o.acknowledged_at,p.processing_deadline-interval '15 minutes',o.lease_expires_at-interval '30 seconds',p.updated_at),p.delivery_deadline,COALESCE(o.lease_expires_at-interval '30 seconds',p.updated_at),LEAST(p.delivery_deadline,clock_timestamp()),clock_timestamp()+interval '5 seconds',true
FROM document_processing p LEFT JOIN document_outbox o ON o.document_id=p.document_id AND o.generation=p.generation JOIN document_processing_jobs j ON j.document_id=p.document_id AND j.generation=p.generation
WHERE p.workflow_id<>'' OR p.run_id<>'' OR p.processing_deadline IS NOT NULL OR o.lease_token IS NOT NULL OR o.acknowledged_at IS NOT NULL;
UPDATE document_processing p SET delivery_deadline=NULL WHERE state IN ('queued','processing') AND NOT EXISTS(SELECT 1 FROM document_processing_executions e WHERE e.document_id=p.document_id AND e.generation=p.generation);
UPDATE document_outbox o SET delivery_deadline=NULL WHERE NOT EXISTS(SELECT 1 FROM document_processing_executions e WHERE e.document_id=o.document_id AND e.generation=o.generation);
ALTER TABLE document_reindex_batches ADD COLUMN needs_aggregation boolean NOT NULL DEFAULT false;
CREATE INDEX document_reindex_batches_aggregate_idx ON document_reindex_batches(created_at,id) WHERE needs_aggregation;
CREATE FUNCTION document_reindex_item_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  UPDATE document_reindex_batches SET needs_aggregation=true WHERE id=OLD.batch_id;
  RETURN OLD;
 END IF;
 UPDATE document_reindex_batches SET needs_aggregation=true WHERE id=NEW.batch_id;
 RETURN NEW;
END
$$;
CREATE TRIGGER document_reindex_item_changed AFTER INSERT OR UPDATE OR DELETE ON document_reindex_items FOR EACH ROW EXECUTE FUNCTION document_reindex_item_changed();
