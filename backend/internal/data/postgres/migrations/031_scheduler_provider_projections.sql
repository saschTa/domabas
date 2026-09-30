ALTER TABLE document_ai_jobs ADD COLUMN scheduler_provider text NOT NULL DEFAULT '';
ALTER TABLE document_ai_jobs ADD COLUMN scheduler_base_url text NOT NULL DEFAULT '';
ALTER TABLE document_processing_jobs ADD COLUMN scheduler_provider text NOT NULL DEFAULT '';
ALTER TABLE document_processing_jobs ADD COLUMN scheduler_base_url text NOT NULL DEFAULT '';
ALTER TABLE document_processing_configuration ADD COLUMN scheduler_provider text NOT NULL DEFAULT '';
ALTER TABLE document_processing_configuration ADD COLUMN scheduler_base_url text NOT NULL DEFAULT '';

CREATE FUNCTION document_scheduler_requirements() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF COALESCE((NEW.configuration->'LLM'->>'Enabled')::boolean,false)
    OR COALESCE((NEW.configuration->'LLM'->>'InvoiceEnabled')::boolean,(NEW.configuration->'LLM'->>'Enabled')::boolean,false) THEN
  NEW.scheduler_provider := COALESCE(NULLIF(NEW.configuration->'LLM'->>'Provider',''),'ollama');
  NEW.scheduler_base_url := COALESCE(NEW.configuration->'LLM'->>'BaseURL','');
 ELSE
  NEW.scheduler_provider := '';
  NEW.scheduler_base_url := '';
 END IF;
 RETURN NEW;
END
$$;
CREATE TRIGGER document_ai_scheduler_requirements BEFORE INSERT OR UPDATE OF configuration ON document_ai_jobs FOR EACH ROW EXECUTE FUNCTION document_scheduler_requirements();
CREATE TRIGGER document_ingestion_scheduler_requirements BEFORE INSERT OR UPDATE OF configuration ON document_processing_jobs FOR EACH ROW EXECUTE FUNCTION document_scheduler_requirements();
CREATE TRIGGER document_configuration_scheduler_requirements BEFORE INSERT OR UPDATE OF configuration ON document_processing_configuration FOR EACH ROW EXECUTE FUNCTION document_scheduler_requirements();
UPDATE document_ai_jobs SET configuration=configuration;
UPDATE document_processing_jobs SET configuration=configuration;
UPDATE document_processing_configuration SET configuration=configuration;
DO $$ BEGIN
 EXECUTE format('ALTER FUNCTION %I.document_scheduler_requirements() SET search_path = %I, pg_catalog, pg_temp',current_schema(),current_schema());
END $$;
