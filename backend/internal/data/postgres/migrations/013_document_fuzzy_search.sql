CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public VERSION '1.6';

DO $$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_extension e
  JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
  WHERE e.extname='pg_trgm' AND e.extversion='1.6' AND n.nspname='public'
 ) THEN
  RAISE EXCEPTION 'Domabas requires pg_trgm version 1.6 in the public schema';
 END IF;
END
$$;

CREATE FUNCTION document_fuzzy_score(words text[], value tsvector) RETURNS double precision
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
 SELECT COALESCE(min(CASE
  WHEN word=ANY(tsvector_to_array(value)) THEN 1::real
  WHEN char_length(word)>=4 AND word ~ '[[:alpha:]]'
   THEN public.strict_word_similarity(word,array_to_string(tsvector_to_array(value),' '))
  ELSE 0::real END),0)::double precision
 FROM unnest(words) word
$$;
