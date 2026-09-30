CREATE TABLE accounts (
    id uuid PRIMARY KEY,
    name text NOT NULL DEFAULT 'Account' CHECK (char_length(name) BETWEEN 1 AND 100),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
    id uuid PRIMARY KEY,
    email text NOT NULL UNIQUE CHECK (email = lower(email) AND octet_length(email) BETWEEN 3 AND 254),
    password_hash text NOT NULL,
    credential_revision bigint NOT NULL DEFAULT 1 CHECK (credential_revision > 0),
    must_change_password boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE memberships (
    account_id uuid NOT NULL REFERENCES accounts(id),
    user_id uuid NOT NULL REFERENCES users(id),
    role text NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
    enabled boolean NOT NULL DEFAULT true,
    PRIMARY KEY (account_id, user_id),
    UNIQUE (user_id)
);

CREATE TABLE sessions (
    digest text PRIMARY KEY CHECK (digest ~ '^[0-9a-f]{64}$'),
    account_id uuid NOT NULL,
    user_id uuid NOT NULL,
    credential_revision bigint NOT NULL CHECK (credential_revision > 0),
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id, user_id) REFERENCES memberships(account_id, user_id)
);

CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);
CREATE INDEX sessions_user_id_idx ON sessions (user_id);

ALTER TABLE documents ADD COLUMN account_id uuid REFERENCES accounts(id);
CREATE INDEX documents_account_created_at_id_idx ON documents (account_id, created_at DESC, id DESC);
