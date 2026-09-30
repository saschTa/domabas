ALTER TABLE document_thumbnail_jobs
 ADD COLUMN updated_at timestamptz,
 ADD COLUMN started_at timestamptz,
 ADD COLUMN finished_at timestamptz;

CREATE INDEX document_thumbnail_jobs_page_idx ON document_thumbnail_jobs(account_id,created_at DESC,id DESC);

CREATE FUNCTION document_thumbnail_job_history_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  NEW.updated_at=NEW.created_at;
 ELSIF NEW.status IS DISTINCT FROM OLD.status OR NEW.failure_code IS DISTINCT FROM OLD.failure_code THEN
  NEW.updated_at=clock_timestamp();
  IF NEW.status='running' AND OLD.status='queued' THEN
   NEW.started_at=NEW.updated_at;
  END IF;
  IF NEW.status IN ('succeeded','failed','obsolete') AND OLD.status IN ('queued','running') THEN
   NEW.finished_at=NEW.updated_at;
  END IF;
 ELSE
  RETURN NEW;
 END IF;
 PERFORM realtime_notify(TG_TABLE_SCHEMA,'document_job',NEW.account_id,NULL);
 RETURN NEW;
END
$$;
CREATE TRIGGER document_thumbnail_job_history_changed BEFORE INSERT OR UPDATE ON document_thumbnail_jobs FOR EACH ROW EXECUTE FUNCTION document_thumbnail_job_history_changed();
DO $$ BEGIN
 EXECUTE format('ALTER FUNCTION %I.document_thumbnail_job_history_changed() SET search_path = %I, pg_catalog, pg_temp',current_schema(),current_schema());
END $$;

CREATE OR REPLACE VIEW document_pipeline_jobs AS
 SELECT id,account_id,document_id,generation,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,created_at,updated_at,started_at,finished_at,initiated_by_user_id,parent_batch_id,extraction_method,extraction_engine,extraction_engine_version,'ingestion'::text pipeline,NULL::bigint attempt,CASE WHEN split_pipeline THEN 2 ELSE 1 END pipeline_version,NULL::integer renderer_revision,NULL::text source_sha256 FROM document_processing_jobs
 UNION ALL
 SELECT id,account_id,document_id,generation,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,created_at,updated_at,started_at,finished_at,initiated_by_user_id,parent_batch_id,NULL::text,NULL::text,NULL::text,'ai',attempt,1,NULL::integer,NULL::text FROM document_ai_jobs
 UNION ALL
 SELECT id,account_id,document_id,NULL::bigint,CASE WHEN attempt=1 THEN 'automatic' ELSE 'retry' END,NULL::bigint,NULL::text,NULL::jsonb,
  CASE WHEN status='obsolete' THEN 'superseded' ELSE status END,
  CASE WHEN status='succeeded' THEN 'complete' WHEN status='running' OR started_at IS NOT NULL THEN 'rendering' WHEN status='queued' THEN 'queued' ELSE 'failed' END,
  NULL::text,NULLIF(failure_code,''),created_at,COALESCE(updated_at,created_at),started_at,finished_at,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::text,'thumbnail',attempt::bigint,1,renderer_revision,source_sha256
 FROM document_thumbnail_jobs;
