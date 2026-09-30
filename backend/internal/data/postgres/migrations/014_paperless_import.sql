CREATE TABLE paperless_runs (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts(id),
    owner_id uuid NOT NULL REFERENCES users(id),
    credential_revision bigint NOT NULL,
    server_url text NOT NULL,
    request_hash bytea NOT NULL,
    encrypted_token bytea,
    state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','running','succeeded','failed','cancelled')),
    stage text NOT NULL DEFAULT 'queued' CHECK (stage IN ('queued','discovering','importing','complete')),
    page integer NOT NULL DEFAULT 1,
    source_total integer,
    cancel_requested boolean NOT NULL DEFAULT false,
    failure_code text NOT NULL DEFAULT '',
    task_queue text NOT NULL,
    first_start_at timestamptz,
    execution_closed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX paperless_runs_owner ON paperless_runs(account_id,owner_id,created_at DESC,id DESC);
CREATE INDEX paperless_runs_admission ON paperless_runs(created_at,id) WHERE NOT execution_closed;
CREATE UNIQUE INDEX paperless_runs_one_active_owner ON paperless_runs(account_id,owner_id) WHERE state IN ('queued','running');

CREATE TABLE paperless_admission (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    run_id uuid REFERENCES paperless_runs(id)
);
INSERT INTO paperless_admission(singleton) VALUES(true);

CREATE TABLE paperless_items (
    run_id uuid NOT NULL REFERENCES paperless_runs(id) ON DELETE CASCADE,
    source_id bigint NOT NULL CHECK (source_id BETWEEN 1 AND 2147483647),
    title text NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','imported','duplicate','failed')),
    failure_code text NOT NULL DEFAULT '',
    document_id uuid,
    PRIMARY KEY (run_id,source_id)
);
