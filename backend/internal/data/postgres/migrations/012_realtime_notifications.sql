CREATE FUNCTION realtime_notify(schema_name text, signal_kind text, account_id uuid DEFAULT NULL, user_id uuid DEFAULT NULL)
RETURNS void LANGUAGE sql VOLATILE AS $$
    SELECT pg_catalog.pg_notify('domabas_rt_' || pg_catalog.md5(schema_name),
        pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'version', 1, 'schema', schema_name, 'kind', signal_kind,
            'account', account_id, 'user', user_id))::text)
$$;

CREATE FUNCTION realtime_documents_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.title, OLD.description, OLD.created_at, OLD.tags, OLD.kind, OLD.sender, OLD.recipients, OLD.cc, OLD.bcc, OLD.document_date, OLD.subject, OLD.message_id, OLD.ocr_revision, OLD.ocr_machine_text, OLD.ocr_manual_text, OLD.machine_extraction_fingerprint, OLD.machine_extracted_at, OLD.machine_extraction_method, OLD.machine_extraction_engine, OLD.machine_extraction_engine_version) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.title, NEW.description, NEW.created_at, NEW.tags, NEW.kind, NEW.sender, NEW.recipients, NEW.cc, NEW.bcc, NEW.document_date, NEW.subject, NEW.message_id, NEW.ocr_revision, NEW.ocr_machine_text, NEW.ocr_manual_text, NEW.machine_extraction_fingerprint, NEW.machine_extracted_at, NEW.machine_extraction_method, NEW.machine_extraction_engine, NEW.machine_extraction_engine_version) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', OLD.account_id, NULL);
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', NEW.account_id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_documents_changed AFTER INSERT OR UPDATE OR DELETE ON documents
FOR EACH ROW EXECUTE FUNCTION realtime_documents_changed();

CREATE FUNCTION realtime_document_files_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.document_id, OLD.original_filename, OLD.media_type, OLD.size, OLD.sha256, OLD.ingested_at, OLD.location) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.document_id, NEW.original_filename, NEW.media_type, NEW.size, NEW.sha256, NEW.ingested_at, NEW.location) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', OLD.account_id, NULL);
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', NEW.account_id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_document_files_changed AFTER INSERT OR UPDATE OR DELETE ON document_files
FOR EACH ROW EXECUTE FUNCTION realtime_document_files_changed();

CREATE FUNCTION realtime_document_processing_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.document_id, OLD.generation, OLD.state, OLD.stage, OLD.configuration_revision, OLD.configuration, OLD.ocr_revision, OLD.failure_code, OLD.extraction_method, OLD.extraction_engine, OLD.extraction_engine_version) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.document_id, NEW.generation, NEW.state, NEW.stage, NEW.configuration_revision, NEW.configuration, NEW.ocr_revision, NEW.failure_code, NEW.extraction_method, NEW.extraction_engine, NEW.extraction_engine_version) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', OLD.account_id, NULL);
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', NEW.account_id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_document_processing_changed AFTER INSERT OR UPDATE OR DELETE ON document_processing
FOR EACH ROW EXECUTE FUNCTION realtime_document_processing_changed();

CREATE FUNCTION realtime_document_processing_jobs_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.document_id, OLD.initiated_by_user_id, OLD.parent_batch_id, OLD.generation, OLD.reason, OLD.configuration_revision, OLD.configuration_fingerprint, OLD.status, OLD.stage, OLD.text_source, OLD.failure_code, OLD.created_at, OLD.started_at, OLD.finished_at, OLD.extraction_method, OLD.extraction_engine, OLD.extraction_engine_version) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.document_id, NEW.initiated_by_user_id, NEW.parent_batch_id, NEW.generation, NEW.reason, NEW.configuration_revision, NEW.configuration_fingerprint, NEW.status, NEW.stage, NEW.text_source, NEW.failure_code, NEW.created_at, NEW.started_at, NEW.finished_at, NEW.extraction_method, NEW.extraction_engine, NEW.extraction_engine_version) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'document_job', OLD.account_id, CASE WHEN OLD.parent_batch_id IS NULL THEN OLD.initiated_by_user_id END);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'document_job', NEW.account_id, CASE WHEN NEW.parent_batch_id IS NULL THEN NEW.initiated_by_user_id END);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_document_processing_jobs_changed AFTER INSERT OR UPDATE OR DELETE ON document_processing_jobs
FOR EACH ROW EXECUTE FUNCTION realtime_document_processing_jobs_changed();

CREATE FUNCTION realtime_document_reindex_batches_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.requester_id, OLD.reason, OLD.configuration_revision, OLD.configuration_fingerprint, OLD.enumeration_complete, OLD.status, OLD.created_at, OLD.finished_at, OLD.discovered, OLD.waiting, OLD.running, OLD.succeeded, OLD.failed, OLD.skipped, OLD.superseded) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.requester_id, NEW.reason, NEW.configuration_revision, NEW.configuration_fingerprint, NEW.enumeration_complete, NEW.status, NEW.created_at, NEW.finished_at, NEW.discovered, NEW.waiting, NEW.running, NEW.succeeded, NEW.failed, NEW.skipped, NEW.superseded) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.reason = 'manual' AND OLD.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'batch', OLD.account_id, OLD.requester_id);
        ELSE
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'configuration', NULL, NULL);
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.reason = 'manual' AND NEW.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'batch', NEW.account_id, NEW.requester_id);
        ELSE
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'configuration', NULL, NULL);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_document_reindex_batches_changed AFTER INSERT OR UPDATE OR DELETE ON document_reindex_batches
FOR EACH ROW EXECUTE FUNCTION realtime_document_reindex_batches_changed();

CREATE FUNCTION realtime_document_processing_configuration_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.revision, OLD.language, OLD.segmentation, OLD.configuration, OLD.fingerprint, OLD.manifest_revision, OLD.manifest_fingerprint, OLD.automatic_batch_id, OLD.adopted) IS NOT DISTINCT FROM ROW(NEW.revision, NEW.language, NEW.segmentation, NEW.configuration, NEW.fingerprint, NEW.manifest_revision, NEW.manifest_fingerprint, NEW.automatic_batch_id, NEW.adopted) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'configuration', NULL, NULL);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'configuration', NULL, NULL);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_document_processing_configuration_changed AFTER INSERT OR UPDATE OR DELETE ON document_processing_configuration
FOR EACH ROW EXECUTE FUNCTION realtime_document_processing_configuration_changed();

CREATE FUNCTION realtime_email_providers_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.owner_id, OLD.label, OLD.host, OLD.port, OLD.mailbox, OLD.enabled, OLD.interval_minutes, OLD.max_age_days, OLD.page_size, OLD.revision, OLD.source_generation, OLD.credential_version, OLD.consent_revision, OLD.deleted_at, OLD.last_run_id, OLD.last_failure_code, OLD.created_at) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.owner_id, NEW.label, NEW.host, NEW.port, NEW.mailbox, NEW.enabled, NEW.interval_minutes, NEW.max_age_days, NEW.page_size, NEW.revision, NEW.source_generation, NEW.credential_version, NEW.consent_revision, NEW.deleted_at, NEW.last_run_id, NEW.last_failure_code, NEW.created_at) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'email', OLD.account_id, OLD.owner_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'email', NEW.account_id, NEW.owner_id);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_email_providers_changed AFTER INSERT OR UPDATE OR DELETE ON email_providers
FOR EACH ROW EXECUTE FUNCTION realtime_email_providers_changed();

CREATE FUNCTION realtime_email_runs_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.owner_id, OLD.provider_id, OLD.provider_revision, OLD.source_generation, OLD.trigger, OLD.status, OLD.stage, OLD.failure_code, OLD.created_at, OLD.started_at, OLD.finished_at, OLD.has_more, OLD.messages_discovered, OLD.messages_accepted, OLD.messages_reused, OLD.messages_skipped, OLD.messages_failed, OLD.messages_with_content_failures, OLD.attachments_accepted, OLD.attachments_reused, OLD.attachments_skipped, OLD.attachments_failed) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.owner_id, NEW.provider_id, NEW.provider_revision, NEW.source_generation, NEW.trigger, NEW.status, NEW.stage, NEW.failure_code, NEW.created_at, NEW.started_at, NEW.finished_at, NEW.has_more, NEW.messages_discovered, NEW.messages_accepted, NEW.messages_reused, NEW.messages_skipped, NEW.messages_failed, NEW.messages_with_content_failures, NEW.attachments_accepted, NEW.attachments_reused, NEW.attachments_skipped, NEW.attachments_failed) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'email', OLD.account_id, OLD.owner_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'email', NEW.account_id, NEW.owner_id);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_email_runs_changed AFTER INSERT OR UPDATE OR DELETE ON email_runs
FOR EACH ROW EXECUTE FUNCTION realtime_email_runs_changed();

CREATE FUNCTION realtime_email_messages_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.parent_document_id) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.parent_document_id) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.parent_document_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM documents WHERE account_id = OLD.account_id AND id = OLD.parent_document_id
        ) THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', OLD.account_id, NULL);
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.parent_document_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM documents WHERE account_id = NEW.account_id AND id = NEW.parent_document_id
        ) THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', NEW.account_id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_email_messages_changed AFTER INSERT OR UPDATE OR DELETE ON email_messages
FOR EACH ROW EXECUTE FUNCTION realtime_email_messages_changed();

CREATE FUNCTION realtime_email_parts_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.message_id, OLD.path, OLD.filename, OLD.media_type, OLD.state, OLD.failure_code, OLD.document_id) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.message_id, NEW.path, NEW.filename, NEW.media_type, NEW.state, NEW.failure_code, NEW.document_id) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.path <> '0' AND EXISTS (
            SELECT 1 FROM email_messages e JOIN documents d
                ON d.account_id = e.account_id AND d.id = e.parent_document_id
            WHERE e.id = OLD.message_id AND e.account_id = OLD.account_id
        ) THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', OLD.account_id, NULL);
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.path <> '0' AND EXISTS (
            SELECT 1 FROM email_messages e JOIN documents d
                ON d.account_id = e.account_id AND d.id = e.parent_document_id
            WHERE e.id = NEW.message_id AND e.account_id = NEW.account_id
        ) THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'documents', NEW.account_id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_email_parts_changed AFTER INSERT OR UPDATE OR DELETE ON email_parts
FOR EACH ROW EXECUTE FUNCTION realtime_email_parts_changed();

CREATE FUNCTION realtime_memberships_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.user_id, OLD.role, OLD.is_owner, OLD.claims, OLD.enabled) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.user_id, NEW.role, NEW.is_owner, NEW.claims, NEW.enabled) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'authority', OLD.account_id, OLD.user_id);
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'members', OLD.account_id, NULL);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'authority', NEW.account_id, NEW.user_id);
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'members', NEW.account_id, NULL);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_memberships_changed AFTER INSERT OR UPDATE OR DELETE ON memberships
FOR EACH ROW EXECUTE FUNCTION realtime_memberships_changed();

CREATE FUNCTION realtime_invitations_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.role, OLD.claims, OLD.email, OLD.issuer_id, OLD.created_at, OLD.expires_at, OLD.accepted_at, OLD.revoked_at) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.role, NEW.claims, NEW.email, NEW.issuer_id, NEW.created_at, NEW.expires_at, NEW.accepted_at, NEW.revoked_at) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'members', OLD.account_id, NULL);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'members', NEW.account_id, NULL);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_invitations_changed AFTER INSERT OR UPDATE OR DELETE ON invitations
FOR EACH ROW EXECUTE FUNCTION realtime_invitations_changed();

CREATE FUNCTION realtime_accounts_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.id, OLD.name) IS NOT DISTINCT FROM ROW(NEW.id, NEW.name) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'account', OLD.id, NULL);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'account', NEW.id, NULL);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_accounts_changed AFTER INSERT OR UPDATE OR DELETE ON accounts
FOR EACH ROW EXECUTE FUNCTION realtime_accounts_changed();

CREATE FUNCTION realtime_users_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    public_changed boolean;
    authority_changed boolean;
BEGIN
    public_changed := TG_OP <> 'UPDATE' OR
        ROW(OLD.id, OLD.email, OLD.system_role, OLD.created_at)
        IS DISTINCT FROM ROW(NEW.id, NEW.email, NEW.system_role, NEW.created_at);
    authority_changed := TG_OP <> 'UPDATE' OR
        ROW(OLD.id, OLD.email, OLD.system_role, OLD.must_change_password, OLD.personal_account_id, OLD.credential_revision)
        IS DISTINCT FROM ROW(NEW.id, NEW.email, NEW.system_role, NEW.must_change_password, NEW.personal_account_id, NEW.credential_revision);
    IF public_changed THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'system_users', NULL, NULL);
    END IF;
    IF authority_changed THEN
        IF TG_OP <> 'INSERT' THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'authority', NULL, OLD.id);
        END IF;
        IF TG_OP <> 'DELETE' THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'authority', NULL, NEW.id);
        END IF;
    END IF;
    IF TG_OP <> 'UPDATE' OR
        ROW(OLD.id, OLD.email, OLD.system_role, OLD.must_change_password, OLD.personal_account_id, OLD.created_at)
        IS DISTINCT FROM ROW(NEW.id, NEW.email, NEW.system_role, NEW.must_change_password, NEW.personal_account_id, NEW.created_at)
    THEN
        IF TG_OP <> 'INSERT' THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'member_user', NULL, OLD.id);
        END IF;
        IF TG_OP <> 'DELETE' THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'member_user', NULL, NEW.id);
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_users_changed AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION realtime_users_changed();

CREATE FUNCTION realtime_sessions_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.digest, OLD.account_id, OLD.user_id, OLD.credential_revision, OLD.expires_at) IS NOT DISTINCT FROM ROW(NEW.digest, NEW.account_id, NEW.user_id, NEW.credential_revision, NEW.expires_at) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'INSERT' THEN
        RETURN NULL;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'authority', OLD.account_id, OLD.user_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'authority', NEW.account_id, NEW.user_id);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_sessions_changed AFTER INSERT OR UPDATE OR DELETE ON sessions
FOR EACH ROW EXECUTE FUNCTION realtime_sessions_changed();

DO $$
DECLARE
    function_name text;
BEGIN
    FOREACH function_name IN ARRAY ARRAY['realtime_documents_changed', 'realtime_document_files_changed', 'realtime_document_processing_changed', 'realtime_document_processing_jobs_changed', 'realtime_document_reindex_batches_changed', 'realtime_document_processing_configuration_changed', 'realtime_email_providers_changed', 'realtime_email_runs_changed', 'realtime_email_messages_changed', 'realtime_email_parts_changed', 'realtime_memberships_changed', 'realtime_invitations_changed', 'realtime_accounts_changed', 'realtime_users_changed', 'realtime_sessions_changed'] LOOP
        EXECUTE format('ALTER FUNCTION %I.%I() SET search_path = %I, pg_catalog, pg_temp',
            current_schema(), function_name, current_schema());
    END LOOP;
END
$$;
