CREATE TABLE documents (
    id uuid PRIMARY KEY,
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
    description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 4000),
    created_at timestamptz NOT NULL
);

CREATE INDEX documents_created_at_id_idx ON documents (created_at DESC, id DESC);
