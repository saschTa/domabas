CREATE FUNCTION realtime_paperless_runs_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.owner_id, OLD.state, OLD.stage, OLD.cancel_requested, OLD.failure_code, OLD.server_url) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.owner_id, NEW.state, NEW.stage, NEW.cancel_requested, NEW.failure_code, NEW.server_url) THEN
        RETURN NULL;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'paperless', OLD.account_id, OLD.owner_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'paperless', NEW.account_id, NEW.owner_id);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_paperless_runs_changed AFTER INSERT OR UPDATE OR DELETE ON paperless_runs
FOR EACH ROW EXECUTE FUNCTION realtime_paperless_runs_changed();

CREATE FUNCTION realtime_chat_turns_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.owner_id, OLD.status, OLD.stage, OLD.failure_code, OLD.finished_at) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.owner_id, NEW.status, NEW.stage, NEW.failure_code, NEW.finished_at) THEN
        RETURN NULL;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', OLD.account_id, OLD.owner_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', NEW.account_id, NEW.owner_id);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_chat_turns_changed AFTER INSERT OR UPDATE OR DELETE ON chat_turns
FOR EACH ROW EXECUTE FUNCTION realtime_chat_turns_changed();

CREATE FUNCTION realtime_chat_conversations_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.owner_id, OLD.title, OLD.deleted_at) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.owner_id, NEW.title, NEW.deleted_at) THEN
        RETURN NULL;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', OLD.account_id, OLD.owner_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', NEW.account_id, NEW.owner_id);
    END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_chat_conversations_changed AFTER INSERT OR UPDATE OR DELETE ON chat_conversations
FOR EACH ROW EXECUTE FUNCTION realtime_chat_conversations_changed();

CREATE FUNCTION realtime_paperless_items_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    parent_id uuid;
    namespace_id uuid;
    user_id uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.run_id, OLD.source_id, OLD.title, OLD.status, OLD.failure_code, OLD.document_id) IS NOT DISTINCT FROM ROW(NEW.run_id, NEW.source_id, NEW.title, NEW.status, NEW.failure_code, NEW.document_id) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'DELETE' THEN parent_id := OLD.run_id; ELSE parent_id := NEW.run_id; END IF;
    SELECT account_id, owner_id INTO namespace_id, user_id FROM paperless_runs WHERE id = parent_id;
    IF FOUND THEN PERFORM realtime_notify(TG_TABLE_SCHEMA, 'paperless', namespace_id, user_id); END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_paperless_items_changed AFTER INSERT OR UPDATE OR DELETE ON paperless_items
FOR EACH ROW EXECUTE FUNCTION realtime_paperless_items_changed();

CREATE FUNCTION realtime_chat_messages_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    parent_id uuid;
    namespace_id uuid;
    user_id uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.turn_id, OLD.content) IS NOT DISTINCT FROM ROW(NEW.turn_id, NEW.content) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'DELETE' THEN parent_id := OLD.turn_id; ELSE parent_id := NEW.turn_id; END IF;
    SELECT account_id, owner_id INTO namespace_id, user_id FROM chat_turns WHERE id = parent_id;
    IF FOUND THEN PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', namespace_id, user_id); END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_chat_messages_changed AFTER INSERT OR UPDATE OR DELETE ON chat_messages
FOR EACH ROW EXECUTE FUNCTION realtime_chat_messages_changed();

CREATE FUNCTION realtime_chat_tool_results_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    parent_id uuid;
    namespace_id uuid;
    user_id uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.turn_id, OLD.ordinal, OLD.kind, OLD.query, OLD.document_id, OLD.text_offset, OLD.result_text, OLD.outcome_code, OLD.next_offset) IS NOT DISTINCT FROM ROW(NEW.turn_id, NEW.ordinal, NEW.kind, NEW.query, NEW.document_id, NEW.text_offset, NEW.result_text, NEW.outcome_code, NEW.next_offset) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'DELETE' THEN parent_id := OLD.turn_id; ELSE parent_id := NEW.turn_id; END IF;
    SELECT account_id, owner_id INTO namespace_id, user_id FROM chat_turns WHERE id = parent_id;
    IF FOUND THEN PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', namespace_id, user_id); END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_chat_tool_results_changed AFTER INSERT OR UPDATE OR DELETE ON chat_tool_results
FOR EACH ROW EXECUTE FUNCTION realtime_chat_tool_results_changed();

CREATE FUNCTION realtime_chat_sources_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    parent_id uuid;
    namespace_id uuid;
    user_id uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.turn_id, OLD.ordinal, OLD.document_id, OLD.title, OLD.excerpt) IS NOT DISTINCT FROM ROW(NEW.turn_id, NEW.ordinal, NEW.document_id, NEW.title, NEW.excerpt) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'DELETE' THEN parent_id := OLD.turn_id; ELSE parent_id := NEW.turn_id; END IF;
    SELECT account_id, owner_id INTO namespace_id, user_id FROM chat_turns WHERE id = parent_id;
    IF FOUND THEN PERFORM realtime_notify(TG_TABLE_SCHEMA, 'chat', namespace_id, user_id); END IF;
    RETURN NULL;
END
$$;
CREATE TRIGGER realtime_chat_sources_changed AFTER INSERT OR UPDATE OR DELETE ON chat_sources
FOR EACH ROW EXECUTE FUNCTION realtime_chat_sources_changed();

CREATE OR REPLACE FUNCTION realtime_document_reindex_batches_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(OLD.account_id, OLD.requester_id, OLD.reason, OLD.configuration_revision, OLD.configuration_fingerprint, OLD.enumeration_complete, OLD.status, OLD.created_at, OLD.finished_at, OLD.discovered, OLD.waiting, OLD.running, OLD.succeeded, OLD.failed, OLD.skipped, OLD.superseded) IS NOT DISTINCT FROM ROW(NEW.account_id, NEW.requester_id, NEW.reason, NEW.configuration_revision, NEW.configuration_fingerprint, NEW.enumeration_complete, NEW.status, NEW.created_at, NEW.finished_at, NEW.discovered, NEW.waiting, NEW.running, NEW.succeeded, NEW.failed, NEW.skipped, NEW.superseded) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'batch', OLD.account_id, OLD.requester_id);
        END IF;
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'configuration', NULL, NULL);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.account_id IS NOT NULL THEN
            PERFORM realtime_notify(TG_TABLE_SCHEMA, 'batch', NEW.account_id, NEW.requester_id);
        END IF;
        PERFORM realtime_notify(TG_TABLE_SCHEMA, 'configuration', NULL, NULL);
    END IF;
    RETURN NULL;
END
$$;

DO $$
DECLARE function_name text;
BEGIN
    FOREACH function_name IN ARRAY ARRAY['realtime_paperless_runs_changed', 'realtime_paperless_items_changed', 'realtime_chat_turns_changed', 'realtime_chat_conversations_changed', 'realtime_chat_messages_changed', 'realtime_chat_tool_results_changed', 'realtime_chat_sources_changed', 'realtime_document_reindex_batches_changed'] LOOP
        EXECUTE format('ALTER FUNCTION %I.%I() SET search_path = %I, pg_catalog', current_schema(), function_name, current_schema());
    END LOOP;
END
$$;
