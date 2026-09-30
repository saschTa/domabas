ALTER TABLE document_processing_configuration ADD COLUMN llm_lm_studio_compatibility boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION document_pipeline_fingerprint(c jsonb) RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT encode(sha256(convert_to('['||string_agg(replace(replace(replace(replace(replace(to_json(v)::text,'<','\u003c'),'>','\u003e'),'&','\u0026'),chr(8232),'\u2028'),chr(8233),'\u2029'),',' ORDER BY position)||']','UTF8')),'hex') FROM (
 SELECT v,position FROM unnest(ARRAY['1',c->>'Language',c->>'Segmentation',c->>'Engine',c->>'EngineVersion',c->>'EmbeddingModel',c->>'EmbeddingDigest',c->>'Dimensions',c->>'ExtractionRevision',c->>'ChunkingRevision',c->>'EmbeddingInputRevision',c->>'IndexingRevision']) WITH ORDINALITY t(v,position)
 UNION ALL
 SELECT CASE WHEN part=0 THEN w->>'Name' ELSE w->>'SHA256' END,12+2*(row_number() OVER(ORDER BY (w->>'Name') COLLATE "C",part))-part FROM jsonb_array_elements(c->'Weights') w CROSS JOIN generate_series(0,1) part
 UNION ALL
 SELECT v,100+position FROM unnest(ARRAY['property-extraction-v1',COALESCE(c->'LLM'->>'Enabled','false'),COALESCE(NULLIF(c->'LLM'->>'Provider',''),'ollama'),COALESCE(NULLIF(c->'LLM'->>'Model',''),'gemma3:4b'),COALESCE(c->'LLM'->>'BaseURL',''),COALESCE(c->'LLM'->>'CredentialID','')]) WITH ORDINALITY t(v,position)
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
 ) fields
$$;
