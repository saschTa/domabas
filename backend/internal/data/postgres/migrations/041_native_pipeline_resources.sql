DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM document_processing_executions WHERE closed_at IS NULL
  UNION ALL SELECT 1 FROM document_ai_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL
  UNION ALL SELECT 1 FROM document_thumbnail_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL
  UNION ALL SELECT 1 FROM email_executions WHERE closed_at IS NULL
  UNION ALL SELECT 1 FROM paperless_runs WHERE first_start_at IS NOT NULL AND NOT execution_closed
  UNION ALL SELECT 1 FROM chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed) THEN
  RAISE EXCEPTION 'Drain admitted jobs with the previous Domabas worker before upgrading';
 END IF;
END $$;

ALTER TABLE scheduler_settings ADD COLUMN executor_epoch bigint NOT NULL DEFAULT 0;
ALTER TABLE document_ai_jobs ADD COLUMN properties_done boolean NOT NULL DEFAULT false;
UPDATE document_ai_jobs SET properties_done=true WHERE stage='complete';
INSERT INTO scheduler_resources(id,label,concurrency_limit) VALUES
 ('pipeline:document_ingestion','Document ingestion',4),
 ('pipeline:document_ai','Document enrichment',4),
 ('pipeline:document_thumbnail','Thumbnail backfill',2),
 ('pipeline:chat','Chat',4),
 ('pipeline:email','Email retrieval',2),
 ('pipeline:paperless','Paperless imports',2),
 ('stage:thumbnail','Thumbnail rendering',2),
 ('stage:ocr','Text recognition',2),
 ('stage:llm','Language model calls',2),
 ('stage:embedding','Embeddings',2),
 ('pipeline:invoice','Invoice extraction',2),
 ('pipeline:tags','Tags and properties',2);

UPDATE scheduler_resources SET concurrency_limit=(SELECT concurrency_limit FROM scheduler_resources WHERE id='worker')
WHERE id IN ('pipeline:document_ingestion','pipeline:document_ai','pipeline:email','pipeline:paperless');
CREATE TABLE scheduler_job_providers (
 workflow_id text REFERENCES scheduler_requests ON DELETE CASCADE,
 resource_id text REFERENCES scheduler_resources,
 PRIMARY KEY(workflow_id,resource_id)
);
CREATE TABLE scheduler_step_permits (
 workflow_id text REFERENCES scheduler_requests ON DELETE CASCADE,
 resource_id text REFERENCES scheduler_resources,
 scope text NOT NULL,
 token uuid NOT NULL,
 PRIMARY KEY(workflow_id,scope,resource_id)
);
CREATE INDEX scheduler_step_usage ON scheduler_step_permits(resource_id);
INSERT INTO scheduler_job_providers SELECT workflow_id,resource_id FROM scheduler_request_resources WHERE resource_id<>'worker';
DELETE FROM scheduler_request_resources WHERE resource_id<>'worker';
INSERT INTO scheduler_request_resources SELECT workflow_id,'pipeline:'||pipeline FROM scheduler_requests WHERE state<>'released';
UPDATE scheduler_settings SET revision=revision+1;

CREATE TABLE native_executions (
 workflow_id text PRIMARY KEY REFERENCES scheduler_requests ON DELETE CASCADE,
 run_id uuid NOT NULL DEFAULT gen_random_uuid(),
 next_step integer NOT NULL DEFAULT 0,
 attempts integer NOT NULL DEFAULT 0,
 outcome text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
