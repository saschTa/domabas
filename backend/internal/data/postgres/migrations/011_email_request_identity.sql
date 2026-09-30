CREATE UNIQUE INDEX email_runs_request_identity_idx ON email_runs(request_id) WHERE request_id IS NOT NULL;
