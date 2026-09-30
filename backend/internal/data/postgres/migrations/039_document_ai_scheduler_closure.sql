CREATE INDEX document_ai_jobs_closed_workflow_idx ON document_ai_jobs(workflow_id) WHERE closed_at IS NOT NULL;
