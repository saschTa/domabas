ALTER TABLE document_processing_admission DROP COLUMN account_id, DROP COLUMN document_id, DROP COLUMN generation;
ALTER TABLE email_admission DROP COLUMN run_id;
ALTER TABLE paperless_admission DROP COLUMN run_id;

ALTER TABLE paperless_runs ADD COLUMN next_check_at timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE INDEX paperless_runs_check_idx ON paperless_runs(next_check_at,created_at,id) WHERE NOT execution_closed AND first_start_at IS NOT NULL;
CREATE INDEX document_processing_executions_document_open_idx ON document_processing_executions(account_id,document_id) WHERE closed_at IS NULL;
