CREATE FUNCTION document_strings_valid(value text[], maximum integer, bytes integer) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT cardinality(value) <= maximum
 AND (cardinality(value) = 0 OR (array_ndims(value) = 1 AND array_lower(value,1) = 1))
 AND array_position(value,NULL) IS NULL
 AND NOT EXISTS(SELECT 1 FROM unnest(value) item WHERE octet_length(item) NOT BETWEEN 1 AND bytes)
$$;
ALTER TABLE documents ADD COLUMN tags text[] NOT NULL DEFAULT '{}' CHECK (document_strings_valid(tags,20,256));
ALTER TABLE documents ADD COLUMN kind text NOT NULL DEFAULT 'document' CHECK (kind IN ('document','letter','email'));
ALTER TABLE documents ADD COLUMN sender text NOT NULL DEFAULT '' CHECK (octet_length(sender)<=1280);
ALTER TABLE documents ADD COLUMN recipients text[] NOT NULL DEFAULT '{}' CHECK(document_strings_valid(recipients,20,1280));
ALTER TABLE documents ADD COLUMN cc text[] NOT NULL DEFAULT '{}' CHECK(document_strings_valid(cc,20,1280));
ALTER TABLE documents ADD COLUMN bcc text[] NOT NULL DEFAULT '{}' CHECK(document_strings_valid(bcc,20,1280));
ALTER TABLE documents ADD COLUMN document_date date;
ALTER TABLE documents ADD COLUMN subject text NOT NULL DEFAULT '' CHECK(octet_length(subject)<=800);
ALTER TABLE documents ADD COLUMN message_id text NOT NULL DEFAULT '' CHECK(octet_length(message_id)<=2048);
ALTER TABLE documents ADD CONSTRAINT documents_account_id_id_key UNIQUE(account_id,id);
ALTER TABLE documents ADD COLUMN metadata_vector tsvector NOT NULL DEFAULT ''::tsvector;
CREATE FUNCTION document_metadata_index() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 NEW.metadata_vector := to_tsvector('simple', concat_ws(' ',NEW.title,NEW.description,NEW.kind,NEW.sender,array_to_string(NEW.tags,' '),array_to_string(NEW.recipients,' '),array_to_string(NEW.cc,' '),array_to_string(NEW.bcc,' '),NEW.subject,NEW.message_id,NEW.document_date::text));
 RETURN NEW;
END
$$;
CREATE TRIGGER document_metadata_index BEFORE INSERT OR UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION document_metadata_index();
UPDATE documents SET title=title;
CREATE INDEX documents_metadata_vector_idx ON documents USING gin(metadata_vector);
CREATE INDEX documents_tags_idx ON documents USING gin(tags);

CREATE TABLE document_processing_configuration (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 language text NOT NULL DEFAULT 'eng+deu' CHECK(language IN ('eng','deu','eng+deu')),
 segmentation text NOT NULL DEFAULT 'auto' CHECK(segmentation IN ('auto','single_block'))
);
INSERT INTO document_processing_configuration(id) VALUES(true);
CREATE TABLE document_uploads (
 id uuid PRIMARY KEY,
 account_id uuid NOT NULL REFERENCES accounts(id),
 uploader_id uuid NOT NULL REFERENCES users(id),
 state text NOT NULL DEFAULT 'receiving' CHECK(state IN ('receiving','accepted','reaping','retiring')),
 expires_at timestamptz NOT NULL,
 original_filename text,
 media_type text CHECK(media_type IN ('image/png','image/jpeg','application/pdf')),
 size bigint CHECK(size BETWEEN 1 AND 20971520),
 sha256 text CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 CHECK((sha256 IS NULL AND original_filename IS NULL AND media_type IS NULL AND size IS NULL) OR (sha256 IS NOT NULL AND original_filename IS NOT NULL AND media_type IS NOT NULL AND size IS NOT NULL))
);
CREATE INDEX document_uploads_reaping_idx ON document_uploads(state,expires_at);
CREATE TABLE document_files (
 document_id uuid PRIMARY KEY,
 account_id uuid NOT NULL,
 uploader_id uuid NOT NULL REFERENCES users(id),
 original_filename text NOT NULL CHECK(octet_length(original_filename) BETWEEN 1 AND 255),
 media_type text NOT NULL CHECK(media_type IN ('image/png','image/jpeg','application/pdf')),
 size bigint NOT NULL CHECK(size BETWEEN 1 AND 20971520),
 sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 ingested_at timestamptz NOT NULL,
 location text NOT NULL DEFAULT 'staged' CHECK(location IN ('staged','final')),
 FOREIGN KEY(account_id,document_id) REFERENCES documents(account_id,id),
 UNIQUE(account_id,sha256)
);
CREATE TABLE document_processing (
 document_id uuid PRIMARY KEY,
 account_id uuid NOT NULL,
 generation bigint NOT NULL CHECK(generation>0),
 state text NOT NULL CHECK(state IN ('queued','processing','ready','failed')),
 stage text NOT NULL CHECK(stage IN ('queued','extracting','embedding','finalizing','complete','failed')),
 configuration_revision bigint NOT NULL CHECK(configuration_revision>0),
 configuration jsonb NOT NULL,
 updated_at timestamptz NOT NULL,
 failure_code text,
 delivery_deadline timestamptz NOT NULL,
 processing_deadline timestamptz,
 workflow_id text NOT NULL DEFAULT '',
 run_id text NOT NULL DEFAULT '',
 next_check_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(account_id,document_id) REFERENCES documents(account_id,id),
 CHECK((state='failed')=(failure_code IS NOT NULL))
);
CREATE INDEX document_processing_pending_idx ON document_processing(next_check_at) WHERE state IN ('queued','processing');
CREATE FUNCTION document_vector_valid(value double precision[]) RETURNS boolean LANGUAGE sql IMMUTABLE STRICT AS $$
 SELECT cardinality(value)=768 AND array_ndims(value)=1 AND array_lower(value,1)=1 AND array_position(value,NULL) IS NULL
 AND NOT EXISTS(SELECT 1 FROM unnest(value) v WHERE v IN ('Infinity'::float8,'-Infinity'::float8,'NaN'::float8))
 AND EXISTS(SELECT 1 FROM unnest(value) v WHERE v<>0)
$$;
CREATE TABLE document_chunks (
 document_id uuid NOT NULL,
 account_id uuid NOT NULL,
 generation bigint NOT NULL CHECK(generation>0),
 position integer NOT NULL CHECK(position BETWEEN 0 AND 255),
 content text NOT NULL CHECK(char_length(content) BETWEEN 1 AND 2048 AND octet_length(content)<=8192),
 content_vector tsvector GENERATED ALWAYS AS(to_tsvector('simple',content)) STORED,
 embedding double precision[] CHECK(document_vector_valid(embedding)),
 model_digest text CHECK(model_digest='0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f'),
 PRIMARY KEY(document_id,generation,position),
 FOREIGN KEY(account_id,document_id) REFERENCES documents(account_id,id),
 CHECK((embedding IS NULL)=(model_digest IS NULL))
);
CREATE INDEX document_chunks_content_idx ON document_chunks USING gin(content_vector);
CREATE INDEX document_chunks_account_idx ON document_chunks(account_id,document_id,generation);
CREATE TABLE document_outbox (
 id uuid PRIMARY KEY,
 account_id uuid NOT NULL,
 document_id uuid NOT NULL,
 generation bigint NOT NULL CHECK(generation>0),
 configuration_revision bigint NOT NULL,
 delivery_deadline timestamptz NOT NULL,
 available_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 lease_token uuid,
 lease_expires_at timestamptz,
 acknowledged_at timestamptz,
 FOREIGN KEY(account_id,document_id) REFERENCES documents(account_id,id),
 UNIQUE(document_id,generation),
 CHECK((lease_token IS NULL)=(lease_expires_at IS NULL))
);
CREATE INDEX document_outbox_delivery_idx ON document_outbox(available_at) WHERE acknowledged_at IS NULL;
