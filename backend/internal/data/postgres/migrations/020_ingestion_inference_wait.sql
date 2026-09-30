ALTER TABLE document_processing_executions
 DROP CONSTRAINT document_processing_executions_execution_timeout_seconds_check,
 ADD CONSTRAINT document_processing_executions_execution_timeout_seconds_check
 CHECK(execution_timeout_seconds IN (0,900));

ALTER TABLE document_processing
 ADD COLUMN unlimited_inference boolean NOT NULL DEFAULT false,
 ADD COLUMN processing_started_at timestamptz;

UPDATE document_processing
 SET processing_started_at=COALESCE(processing_deadline-interval '15 minutes',updated_at)
 WHERE processing_deadline IS NOT NULL OR workflow_id<>'' OR state='processing';
