ALTER TABLE chat_tool_results ADD COLUMN outcome_code text NOT NULL DEFAULT 'progress';
ALTER TABLE chat_tool_results ADD COLUMN next_offset integer;

UPDATE chat_tool_results r SET
 next_offset=(r.result_text::jsonb->>'nextOffset')::integer,
 outcome_code=CASE
  WHEN r.result_text::jsonb->>'error'='document_unavailable' THEN 'document_unavailable'
  WHEN r.kind='read_document' AND COALESCE(r.result_text::jsonb->>'text','')='' THEN 'empty_result'
  WHEN r.kind IN ('list_tools','search_documents') AND jsonb_array_length(r.result_text::jsonb->'items')=0 THEN 'empty_result'
  WHEN r.kind='search_documents' AND NOT EXISTS (
   SELECT 1 FROM chat_sources s WHERE s.turn_id=r.turn_id AND s.ordinal=r.ordinal
    AND NOT EXISTS(SELECT 1 FROM chat_sources p WHERE p.turn_id=s.turn_id AND p.ordinal<s.ordinal AND p.document_id=s.document_id)
  ) THEN 'no_new_evidence'
  WHEN EXISTS(SELECT 1 FROM chat_tool_results p WHERE p.turn_id=r.turn_id AND p.ordinal<r.ordinal AND p.kind=r.kind AND p.query=r.query AND p.document_id IS NOT DISTINCT FROM r.document_id AND p.text_offset=r.text_offset) THEN 'no_new_evidence'
  ELSE 'progress'
 END;

ALTER TABLE chat_tool_results ADD CONSTRAINT chat_tool_outcome_check CHECK(outcome_code IN ('progress','empty_result','no_new_evidence','document_unavailable','repeated_call','unknown_document','invalid_offset','error_query'));
ALTER TABLE chat_tool_results ADD CONSTRAINT chat_tool_next_offset_check CHECK(next_offset>text_offset);
