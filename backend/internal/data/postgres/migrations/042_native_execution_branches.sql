CREATE TABLE native_execution_branches (
 workflow_id text REFERENCES native_executions ON DELETE CASCADE,
 branch text NOT NULL,
 attempts integer NOT NULL DEFAULT 0,
 outcome text NOT NULL DEFAULT '',
 PRIMARY KEY(workflow_id,branch)
);
