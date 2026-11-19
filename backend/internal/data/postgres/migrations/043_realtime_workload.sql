CREATE FUNCTION realtime_workload_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM realtime_notify(TG_TABLE_SCHEMA, 'workload');
    RETURN NULL;
END
$$;

DO $$
BEGIN
    EXECUTE format('ALTER FUNCTION %I.realtime_workload_changed() SET search_path = %I, pg_catalog', current_schema(), current_schema());
END
$$;

CREATE TRIGGER realtime_workload_scheduler_step_permits
AFTER INSERT OR DELETE ON scheduler_step_permits
FOR EACH ROW EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_scheduler_requests_insert
AFTER INSERT ON scheduler_requests
FOR EACH ROW WHEN (NEW.state = 'active') EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_scheduler_requests_delete
AFTER DELETE ON scheduler_requests
FOR EACH ROW WHEN (OLD.state = 'active') EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_scheduler_requests_update
AFTER UPDATE OF state ON scheduler_requests
FOR EACH ROW WHEN ((OLD.state = 'active') IS DISTINCT FROM (NEW.state = 'active')) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_paperless_items_insert
AFTER INSERT ON paperless_items
FOR EACH ROW WHEN (NEW.claim_token IS NOT NULL) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_paperless_items_delete
AFTER DELETE ON paperless_items
FOR EACH ROW WHEN (OLD.claim_token IS NOT NULL) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_paperless_items_update
AFTER UPDATE OF claim_token ON paperless_items
FOR EACH ROW WHEN ((OLD.claim_token IS NOT NULL) IS DISTINCT FROM (NEW.claim_token IS NOT NULL)) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_scheduler_resources
AFTER INSERT OR DELETE ON scheduler_resources
FOR EACH ROW EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_scheduler_settings_update
AFTER UPDATE OF revision, ollama_queue_size ON scheduler_settings
FOR EACH ROW WHEN (OLD.revision IS DISTINCT FROM NEW.revision OR OLD.ollama_queue_size IS DISTINCT FROM NEW.ollama_queue_size) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_paperless_admission_update
AFTER UPDATE OF retrieval_concurrency ON paperless_admission
FOR EACH ROW WHEN (OLD.retrieval_concurrency IS DISTINCT FROM NEW.retrieval_concurrency) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_chat_configuration_update
AFTER UPDATE OF enabled, provider, base_url ON chat_configuration
FOR EACH ROW WHEN (OLD.enabled IS DISTINCT FROM NEW.enabled OR OLD.provider IS DISTINCT FROM NEW.provider OR OLD.base_url IS DISTINCT FROM NEW.base_url) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_document_processing_configuration_update
AFTER UPDATE OF scheduler_provider, scheduler_base_url ON document_processing_configuration
FOR EACH ROW WHEN (OLD.scheduler_provider IS DISTINCT FROM NEW.scheduler_provider OR OLD.scheduler_base_url IS DISTINCT FROM NEW.scheduler_base_url) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_scheduler_resources_update
AFTER UPDATE OF concurrency_limit, label ON scheduler_resources
FOR EACH ROW WHEN (OLD.concurrency_limit IS DISTINCT FROM NEW.concurrency_limit OR OLD.label IS DISTINCT FROM NEW.label) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_document_processing_executions
AFTER UPDATE OF closed_at ON document_processing_executions
FOR EACH ROW WHEN (OLD.closed_at IS DISTINCT FROM NEW.closed_at) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_document_ai_jobs
AFTER UPDATE OF closed_at ON document_ai_jobs
FOR EACH ROW WHEN (OLD.closed_at IS DISTINCT FROM NEW.closed_at) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_document_thumbnail_jobs
AFTER UPDATE OF closed_at ON document_thumbnail_jobs
FOR EACH ROW WHEN (OLD.closed_at IS DISTINCT FROM NEW.closed_at) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_email_executions
AFTER UPDATE OF closed_at ON email_executions
FOR EACH ROW WHEN (OLD.closed_at IS DISTINCT FROM NEW.closed_at) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_chat_turns
AFTER UPDATE OF execution_closed ON chat_turns
FOR EACH ROW WHEN (OLD.execution_closed IS DISTINCT FROM NEW.execution_closed) EXECUTE FUNCTION realtime_workload_changed();

CREATE TRIGGER realtime_workload_paperless_runs
AFTER UPDATE OF execution_closed ON paperless_runs
FOR EACH ROW WHEN (OLD.execution_closed IS DISTINCT FROM NEW.execution_closed) EXECUTE FUNCTION realtime_workload_changed();
