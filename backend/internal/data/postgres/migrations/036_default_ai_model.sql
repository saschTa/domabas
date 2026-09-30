ALTER TABLE chat_configuration ALTER COLUMN model SET DEFAULT 'qwen3.5:4b';

UPDATE chat_configuration SET model='qwen3.5:4b'
WHERE singleton AND revision=1 AND provider='ollama' AND model='gemma3:4b'
AND EXISTS (
 SELECT 1 FROM schema_migrations
 WHERE version='026_ai_chat.sql' AND applied_at=transaction_timestamp()
);
