ALTER TABLE chat_tool_results DROP CONSTRAINT chat_tool_results_ordinal_check;
ALTER TABLE chat_tool_results ADD CONSTRAINT chat_tool_results_ordinal_check CHECK(ordinal BETWEEN 0 AND 29);
ALTER TABLE chat_tool_results DROP CONSTRAINT chat_tool_results_kind_check;
ALTER TABLE chat_tool_results ADD CONSTRAINT chat_tool_results_kind_check CHECK(kind IN ('list_tools','search_documents','read_document'));
