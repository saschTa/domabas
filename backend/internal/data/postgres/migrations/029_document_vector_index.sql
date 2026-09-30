DO $$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_extension e
  JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
  WHERE e.extname='vector' AND e.extversion='0.8.6' AND n.nspname='public'
 ) THEN
  RAISE EXCEPTION 'Domabas requires pgvector 0.8.6 in public; run database-init with the pgvector PostgreSQL image before migrating';
 END IF;
END
$$;

CREATE INDEX document_chunks_embedding_cosine_idx
 ON document_chunks USING hnsw ((embedding::public.vector(768)) public.vector_cosine_ops)
 WHERE embedding IS NOT NULL;

CREATE STATISTICS document_processing_embedding_space_stats
 ON (configuration->>'EmbeddingModel'), (configuration->>'EmbeddingDigest'),
 ((configuration->>'Dimensions')::integer), (configuration->>'EmbeddingInputRevision'),
 (configuration->>'IndexingRevision')
 FROM document_processing;

ANALYZE document_processing;
ANALYZE document_chunks;
