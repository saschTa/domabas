CREATE TABLE identity_setup (
    id boolean PRIMARY KEY DEFAULT true CHECK (id),
    bootstrap_eligible boolean NOT NULL
);

INSERT INTO identity_setup (id, bootstrap_eligible)
SELECT true, NOT EXISTS (SELECT 1 FROM users)
    AND NOT EXISTS (SELECT 1 FROM accounts)
    AND NOT EXISTS (SELECT 1 FROM documents);

CREATE FUNCTION identity_claims_valid(value text[]) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT cardinality(value) <= 32
        AND (cardinality(value) = 0 OR (array_ndims(value) = 1 AND array_lower(value, 1) = 1))
        AND array_position(value, NULL) IS NULL
        AND NOT EXISTS (SELECT 1 FROM unnest(value) AS claim WHERE octet_length(claim) NOT BETWEEN 1 AND 64)
$$;

ALTER TABLE users ADD COLUMN system_role text NOT NULL DEFAULT 'user'
    CHECK (system_role IN ('admin', 'user'));
ALTER TABLE users ADD COLUMN personal_account_id uuid;
ALTER TABLE memberships DROP CONSTRAINT memberships_user_id_key;
ALTER TABLE memberships ADD COLUMN is_owner boolean NOT NULL DEFAULT false;
ALTER TABLE memberships ADD COLUMN claims text[] NOT NULL DEFAULT '{}'
    CHECK (identity_claims_valid(claims));

UPDATE memberships SET is_owner = true WHERE role = 'owner';
ALTER TABLE memberships DROP CONSTRAINT memberships_role_check;
UPDATE memberships SET role = CASE role WHEN 'owner' THEN 'admin' WHEN 'editor' THEN 'user' ELSE role END;
ALTER TABLE memberships ADD CONSTRAINT memberships_role_check CHECK (role IN ('admin', 'user', 'viewer'));

UPDATE users SET personal_account_id = selected.account_id
FROM (
    SELECT DISTINCT ON (m.account_id) m.account_id, m.user_id
    FROM memberships m JOIN users u ON u.id = m.user_id
    WHERE m.is_owner AND m.enabled
    ORDER BY m.account_id, u.created_at, u.id
) selected
WHERE users.id = selected.user_id;

UPDATE users SET personal_account_id = gen_random_uuid() WHERE personal_account_id IS NULL;
INSERT INTO accounts (id, name, created_at)
SELECT u.personal_account_id, left(u.email, 100), u.created_at FROM users u
WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.id = u.personal_account_id);
INSERT INTO memberships (account_id, user_id, role, enabled, is_owner, claims)
SELECT u.personal_account_id, u.id, 'admin', true, true, '{}' FROM users u
WHERE NOT EXISTS (SELECT 1 FROM memberships m WHERE m.account_id = u.personal_account_id AND m.user_id = u.id);

ALTER TABLE users ALTER COLUMN personal_account_id SET NOT NULL;
ALTER TABLE users ADD CONSTRAINT users_personal_account_key UNIQUE (personal_account_id);
ALTER TABLE users ADD CONSTRAINT users_personal_membership_fk
    FOREIGN KEY (personal_account_id, id) REFERENCES memberships (account_id, user_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE invitations (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts(id),
    issuer_id uuid NOT NULL,
    email text NOT NULL CHECK (email = lower(email) AND octet_length(email) BETWEEN 3 AND 254),
    role text NOT NULL CHECK (role IN ('admin', 'user', 'viewer')),
    claims text[] NOT NULL DEFAULT '{}' CHECK (identity_claims_valid(claims)),
    digest text NOT NULL UNIQUE CHECK (digest ~ '^[0-9a-f]{64}$'),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
    accepted_at timestamptz,
    revoked_at timestamptz,
    FOREIGN KEY (account_id, issuer_id) REFERENCES memberships (account_id, user_id),
    CHECK (accepted_at IS NULL OR revoked_at IS NULL)
);

CREATE INDEX invitations_account_created_id_idx ON invitations (account_id, created_at DESC, id DESC);
CREATE INDEX memberships_user_id_idx ON memberships (user_id);
