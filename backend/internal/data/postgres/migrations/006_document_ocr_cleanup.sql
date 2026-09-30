ALTER TABLE documents ADD COLUMN ocr_machine_text text CHECK(octet_length(ocr_machine_text)<=524288);
ALTER TABLE documents ADD COLUMN ocr_manual_text text CHECK(octet_length(ocr_manual_text)<=524288);
ALTER TABLE documents ADD COLUMN ocr_revision bigint NOT NULL DEFAULT 0 CHECK(ocr_revision>=0);
ALTER TABLE document_processing ADD COLUMN ocr_revision bigint NOT NULL DEFAULT 0 CHECK(ocr_revision>=0);
CREATE TABLE document_cleanup (
 document_id uuid PRIMARY KEY,
 account_id uuid NOT NULL,
 uploader_id uuid NOT NULL,
 next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 lease_token uuid,
 lease_expires_at timestamptz,
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 CHECK((lease_token IS NULL)=(lease_expires_at IS NULL))
);
CREATE INDEX document_cleanup_due_idx ON document_cleanup(next_attempt_at,document_id);
