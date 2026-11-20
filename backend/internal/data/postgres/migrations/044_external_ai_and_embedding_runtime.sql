ALTER TABLE chat_configuration ALTER COLUMN enabled SET DEFAULT false,
 ALTER COLUMN provider SET DEFAULT 'openai', ALTER COLUMN model SET DEFAULT '',
 ALTER COLUMN internal_runtime SET DEFAULT false;
UPDATE chat_configuration SET enabled=false,provider='openai',model='',base_url='',credential_id=NULL,
 internal_runtime=false,revision=revision+1,updated_at=clock_timestamp() WHERE provider='ollama';
UPDATE chat_configuration SET internal_runtime=false WHERE internal_runtime;
ALTER TABLE chat_configuration DROP CONSTRAINT chat_configuration_provider_check,
 ADD CONSTRAINT chat_configuration_provider_check CHECK(provider='openai');

CREATE TEMPORARY TABLE retired_provider_workflows ON COMMIT DROP AS
 WITH chat AS (
  UPDATE chat_turns SET status='failed',stage='failed',failure_code='configuration_unavailable',
   execution_closed=true,finished_at=clock_timestamp(),updated_at=clock_timestamp(),
   execution_token=NULL,execution_expires_at=NULL,delivery_token=NULL,delivery_expires_at=NULL
   WHERE provider='ollama' AND status IN ('queued','running') RETURNING workflow_id
 ), enrichment AS (
  UPDATE document_ai_jobs SET status='failed',stage='failed',failure_code='configuration_unavailable',
   finished_at=clock_timestamp(),closed_at=clock_timestamp(),updated_at=clock_timestamp(),
   lease_token=NULL,lease_expires_at=NULL WHERE scheduler_provider='ollama' AND status IN ('queued','running')
   RETURNING 'document-ai-v1/'||account_id::text||'/'||document_id::text||'/'||generation::text||'/'||attempt::text AS workflow_id
 ) SELECT workflow_id FROM chat UNION ALL SELECT workflow_id FROM enrichment;
UPDATE scheduler_requests q SET state='released',released_at=clock_timestamp(),blocks_admission=false
 FROM retired_provider_workflows w WHERE q.workflow_id=w.workflow_id AND q.state<>'released';
UPDATE native_executions n SET outcome='failed' FROM retired_provider_workflows w WHERE n.workflow_id=w.workflow_id AND n.outcome='';
DELETE FROM scheduler_step_permits p USING retired_provider_workflows w WHERE p.workflow_id=w.workflow_id;

ALTER TABLE scheduler_settings RENAME COLUMN ollama_queue_size TO embedding_queue_size;
INSERT INTO scheduler_resources(id,label,concurrency_limit) SELECT 'embedding-runtime','Local embeddings',concurrency_limit FROM scheduler_resources WHERE id='ollama';
UPDATE scheduler_request_resources SET resource_id='embedding-runtime' WHERE resource_id='ollama';
UPDATE scheduler_job_providers SET resource_id='embedding-runtime' WHERE resource_id='ollama';
UPDATE scheduler_step_permits SET resource_id='embedding-runtime' WHERE resource_id='ollama';
DELETE FROM scheduler_resources WHERE id='ollama';
UPDATE scheduler_settings SET initialized=false,revision=revision+1;

CREATE OR REPLACE FUNCTION document_pipeline_fingerprint(c jsonb) RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT encode(sha256(convert_to('['||string_agg(replace(replace(replace(replace(replace(to_json(v)::text,'<','\u003c'),'>','\u003e'),'&','\u0026'),chr(8232),'\u2028'),chr(8233),'\u2029'),',' ORDER BY position)||']','UTF8')),'hex') FROM (
 SELECT v,position FROM unnest(ARRAY['1',c->>'Language',c->>'Segmentation',c->>'Engine',c->>'EngineVersion',c->>'EmbeddingModel',c->>'EmbeddingDigest',c->>'Dimensions',c->>'ExtractionRevision',c->>'ChunkingRevision',c->>'EmbeddingInputRevision',c->>'IndexingRevision']) WITH ORDINALITY t(v,position)
 UNION ALL
 SELECT CASE WHEN part=0 THEN w->>'Name' ELSE w->>'SHA256' END,12+2*(row_number() OVER(ORDER BY (w->>'Name') COLLATE "C",part))-part FROM jsonb_array_elements(c->'Weights') w CROSS JOIN generate_series(0,1) part
 UNION ALL
 SELECT v,100+position FROM unnest(ARRAY['property-extraction-v1',COALESCE(c->'LLM'->>'Enabled','false'),COALESCE(NULLIF(c->'LLM'->>'Provider',''),'ollama'),CASE WHEN c->'LLM'->>'Provider'='openai' THEN COALESCE(c->'LLM'->>'Model','') ELSE COALESCE(NULLIF(c->'LLM'->>'Model',''),'gemma3:4b') END,COALESCE(c->'LLM'->>'BaseURL',''),COALESCE(c->'LLM'->>'CredentialID','')]) WITH ORDINALITY t(v,position)
 WHERE COALESCE((c->'LLM'->>'Enabled')::boolean,false) OR COALESCE(c->'LLM'->>'Provider','') NOT IN ('','ollama') OR COALESCE(c->'LLM'->>'Model','') NOT IN ('','gemma3:4b') OR COALESCE(c->'LLM'->>'BaseURL','')<>'' OR COALESCE(c->'LLM'->>'CredentialID','')<>''

 UNION ALL
 SELECT v,200+position FROM unnest(ARRAY['invoice-extraction-v1',COALESCE(c->'LLM'->>'InvoiceEnabled',c->'LLM'->>'Enabled','false')]) WITH ORDINALITY t(v,position)
 WHERE COALESCE((c->'LLM'->>'InvoiceEnabled')::boolean,(c->'LLM'->>'Enabled')::boolean,false) <> COALESCE((c->'LLM'->>'Enabled')::boolean,false)
 UNION ALL
 SELECT v,300+position FROM unnest(ARRAY['model-context-v1',c->'LLM'->>'ContextLength']) WITH ORDINALITY t(v,position)
 WHERE COALESCE((c->'LLM'->>'ContextLength')::integer,0)<>0
 UNION ALL
 SELECT v,400+position FROM unnest(ARRAY['lm-studio-compatibility-v1','true']) WITH ORDINALITY t(v,position)
 WHERE COALESCE((c->'LLM'->>'LMStudioCompatibility')::boolean,false)
 UNION ALL
 SELECT v,500+position FROM unnest(ARRAY['property-thinking-v1','true']) WITH ORDINALITY t(v,position)
 WHERE COALESCE((c->'LLM'->>'PropertyThinkingEnabled')::boolean,false)
 UNION ALL
 SELECT v,600+position FROM unnest(ARRAY['invoice-thinking-v1','true']) WITH ORDINALITY t(v,position)
 WHERE COALESCE((c->'LLM'->>'InvoiceThinkingEnabled')::boolean,false)
 ) fields
$$;
