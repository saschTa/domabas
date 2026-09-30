CREATE TABLE document_thumbnails (
 account_id uuid NOT NULL,
 document_id uuid NOT NULL,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
 renderer_revision integer NOT NULL CHECK(renderer_revision > 0),
 sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 media_type text NOT NULL CHECK(media_type='image/jpeg'),
 width integer NOT NULL CHECK(width BETWEEN 1 AND 256),
 height integer NOT NULL CHECK(height BETWEEN 1 AND 360),
 size bigint NOT NULL CHECK(size BETWEEN 1 AND 262144),
 content bytea NOT NULL CHECK(octet_length(content)=size),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(account_id,document_id),
 FOREIGN KEY(account_id,document_id) REFERENCES documents(account_id,id) ON DELETE CASCADE
);
CREATE TABLE document_thumbnail_scan (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 next_scan_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 cursor_account uuid,
 cursor_document uuid,
 upper_account uuid,
 upper_document uuid
);
INSERT INTO document_thumbnail_scan DEFAULT VALUES;
CREATE TABLE document_thumbnail_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 account_id uuid NOT NULL,
 document_id uuid NOT NULL,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
 renderer_revision integer NOT NULL CHECK(renderer_revision > 0),
 attempt integer NOT NULL DEFAULT 1 CHECK(attempt > 0),
 status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','succeeded','failed','obsolete')),
 retryable boolean NOT NULL DEFAULT false,
 failure_code text NOT NULL DEFAULT '',
 available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 workflow_id text NOT NULL,
 task_queue text NOT NULL DEFAULT '',
 run_id text NOT NULL DEFAULT '',
 lease_token uuid,
 lease_until timestamptz,
 permit_end timestamptz,
 admitted_at timestamptz,
 next_check_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 closed_at timestamptz,
 UNIQUE(account_id,document_id,source_sha256,renderer_revision,attempt)
);
CREATE INDEX document_thumbnail_jobs_waiting_idx ON document_thumbnail_jobs(available_at,created_at,id) WHERE status='queued';
CREATE INDEX document_thumbnail_jobs_open_idx ON document_thumbnail_jobs(next_check_at,id) WHERE admitted_at IS NOT NULL AND closed_at IS NULL;
CREATE INDEX document_thumbnail_jobs_identity_idx ON document_thumbnail_jobs(account_id,document_id,source_sha256,renderer_revision,attempt DESC);
ALTER TABLE scheduler_requests DROP CONSTRAINT scheduler_requests_pipeline_check;
ALTER TABLE scheduler_requests ADD CHECK(pipeline IN ('document_ingestion','document_ai','document_thumbnail','chat','email','paperless'));
CREATE FUNCTION realtime_document_thumbnail_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM realtime_notify(TG_TABLE_SCHEMA,'documents',NEW.account_id,NULL);
 RETURN NEW;
END $$;
CREATE TRIGGER realtime_document_thumbnail_changed AFTER INSERT OR UPDATE ON document_thumbnails FOR EACH ROW EXECUTE FUNCTION realtime_document_thumbnail_changed();
DO $$ BEGIN
 EXECUTE format('ALTER FUNCTION %I.realtime_document_thumbnail_changed() SET search_path = %I, pg_catalog, pg_temp',current_schema(),current_schema());
END $$;
