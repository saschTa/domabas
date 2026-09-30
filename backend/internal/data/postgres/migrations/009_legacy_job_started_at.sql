CREATE OR REPLACE FUNCTION document_processing_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  UPDATE document_processing_jobs SET status='cancelled',failure_code='document_deleted',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND generation=OLD.generation AND status IN ('queued','running');
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND OLD.generation<>NEW.generation THEN
  UPDATE document_processing_jobs SET status='superseded',finished_at=clock_timestamp(),updated_at=clock_timestamp() WHERE account_id=OLD.account_id AND document_id=OLD.document_id AND generation=OLD.generation AND status IN ('queued','running');
 END IF;
 INSERT INTO document_processing_jobs(account_id,document_id,generation,generation_sequence,requires_extraction,reason,configuration_revision,configuration_fingerprint,configuration,status,stage,text_source,failure_code,started_at,finished_at,updated_at)
 VALUES(NEW.account_id,NEW.document_id,NEW.generation,NEW.generation_sequence,NEW.requires_extraction,NEW.reason,NEW.configuration_revision,NEW.configuration->>'Fingerprint',NEW.configuration,CASE NEW.state WHEN 'processing' THEN 'running' WHEN 'ready' THEN 'succeeded' ELSE NEW.state END,NEW.stage,CASE WHEN (SELECT ocr_manual_text FROM documents WHERE id=NEW.document_id) IS NULL THEN 'machine' ELSE 'manual' END,NEW.failure_code,CASE WHEN NEW.state='processing' AND NEW.reason<>'legacy' THEN clock_timestamp() END,CASE WHEN NEW.state IN ('ready','failed') THEN clock_timestamp() END,NEW.updated_at)
 ON CONFLICT(account_id,document_id,generation) DO UPDATE SET status=EXCLUDED.status,stage=CASE WHEN EXCLUDED.status='failed' THEN document_processing_jobs.stage ELSE EXCLUDED.stage END,failure_code=EXCLUDED.failure_code,started_at=COALESCE(document_processing_jobs.started_at,EXCLUDED.started_at),finished_at=COALESCE(document_processing_jobs.finished_at,EXCLUDED.finished_at),updated_at=EXCLUDED.updated_at WHERE document_processing_jobs.status IN ('queued','running');
 RETURN NEW;
END
$$;
UPDATE document_processing_jobs SET started_at=NULL WHERE reason='legacy';
