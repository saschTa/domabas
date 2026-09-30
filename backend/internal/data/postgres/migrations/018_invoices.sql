ALTER TABLE document_processing ADD COLUMN invoice_xml bytea CHECK(octet_length(invoice_xml)<=2097152);
ALTER TABLE document_processing ADD COLUMN invoice_completed_generation bigint;
ALTER TABLE document_processing ADD COLUMN invoice_next_stage text CHECK(invoice_next_stage IN ('enriching','embedding','finalizing'));
ALTER TABLE document_processing DROP CONSTRAINT document_processing_stage_check;
ALTER TABLE document_processing ADD CONSTRAINT document_processing_stage_check CHECK(stage IN ('queued','extracting','invoicing','enriching','embedding','finalizing','complete','failed'));
CREATE TABLE invoices (
 id uuid PRIMARY KEY,
 account_id uuid NOT NULL,
 document_id uuid NOT NULL,
 generation bigint NOT NULL CHECK(generation>0),
 ocr_revision bigint NOT NULL CHECK(ocr_revision>=0),
 source text NOT NULL CHECK(source IN ('structured','ai')),
 format text NOT NULL,
 number text NOT NULL CHECK(octet_length(number) BETWEEN 1 AND 16000),
 type_code text NOT NULL,
 issue_date date,
 due_date date,
 seller_name text NOT NULL,
 seller_tax_id text NOT NULL,
 seller_registration_id text NOT NULL,
 seller_address text NOT NULL,
 seller_country text NOT NULL,
 seller_email text NOT NULL,
 buyer_name text NOT NULL,
 buyer_tax_id text NOT NULL,
 buyer_registration_id text NOT NULL,
 buyer_address text NOT NULL,
 buyer_country text NOT NULL,
 buyer_email text NOT NULL,
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 tax_currency text CHECK(tax_currency ~ '^[A-Z]{3}$'),
 total_net numeric,
 total_tax numeric,
 total_gross numeric,
 amount_due numeric,
 paid_amount numeric,
 rounding_amount numeric,
 tax_accounting_amount numeric,
 profile text NOT NULL,
 extraction_model text NOT NULL,
 payment_means_code text NOT NULL,
 payment_reference text NOT NULL,
 payment_iban text NOT NULL,
 payment_bic text NOT NULL,
 payment_terms text NOT NULL,
 search_vector tsvector NOT NULL DEFAULT ''::tsvector,
 source_xml bytea CHECK(octet_length(source_xml)<=2097152),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(account_id,document_id) REFERENCES documents(account_id,id) ON DELETE CASCADE,
 UNIQUE(account_id,document_id),
 UNIQUE(account_id,id),
 CHECK((source='structured')=(source_xml IS NOT NULL))
);
CREATE TABLE invoice_lines (
 account_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 position smallint NOT NULL CHECK(position BETWEEN 0 AND 199),
 line_id text NOT NULL,
 description text NOT NULL,
 quantity numeric,
 unit_code text NOT NULL,
 unit_price numeric,
 net_amount numeric,
 tax_category text NOT NULL,
 tax_rate numeric,
 PRIMARY KEY(invoice_id,position),
 FOREIGN KEY(account_id,invoice_id) REFERENCES invoices(account_id,id) ON DELETE CASCADE
);
CREATE TABLE invoice_taxes (
 account_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 position smallint NOT NULL CHECK(position BETWEEN 0 AND 49),
 category text NOT NULL,
 rate numeric,
 taxable_amount numeric,
 tax_amount numeric,
 exemption_reason text NOT NULL,
 PRIMARY KEY(invoice_id,position),
 FOREIGN KEY(account_id,invoice_id) REFERENCES invoices(account_id,id) ON DELETE CASCADE
);
CREATE TABLE invoice_allowances (
 account_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 position smallint NOT NULL CHECK(position BETWEEN 0 AND 99),
 charge boolean NOT NULL,
 reason text NOT NULL,
 amount numeric,
 tax_category text NOT NULL,
 tax_rate numeric,
 PRIMARY KEY(invoice_id,position),
 FOREIGN KEY(account_id,invoice_id) REFERENCES invoices(account_id,id) ON DELETE CASCADE
);
CREATE TABLE invoice_references (
 account_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 position smallint NOT NULL CHECK(position BETWEEN 0 AND 49),
 number text NOT NULL,
 issue_date date,
 PRIMARY KEY(invoice_id,position),
 FOREIGN KEY(account_id,invoice_id) REFERENCES invoices(account_id,id) ON DELETE CASCADE
);
CREATE TABLE invoice_notes (
 account_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 position smallint NOT NULL CHECK(position BETWEEN 0 AND 49),
 content text NOT NULL,
 PRIMARY KEY(invoice_id,position),
 FOREIGN KEY(account_id,invoice_id) REFERENCES invoices(account_id,id) ON DELETE CASCADE
);
CREATE INDEX invoices_page_idx ON invoices(account_id,created_at DESC,id DESC);
CREATE INDEX invoices_source_page_idx ON invoices(account_id,source,created_at DESC,id DESC);
CREATE INDEX invoices_reference_idx ON invoices(account_id,number,seller_tax_id,seller_registration_id);
CREATE INDEX invoices_search_vector_idx ON invoices USING gin(search_vector);
CREATE FUNCTION realtime_invoices_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  PERFORM realtime_notify(TG_TABLE_SCHEMA,'documents',OLD.account_id,NULL);
 ELSE
  PERFORM realtime_notify(TG_TABLE_SCHEMA,'documents',NEW.account_id,NULL);
 END IF;
 RETURN NULL;
END
$$;
CREATE TRIGGER realtime_invoices_changed AFTER INSERT OR UPDATE OR DELETE ON invoices FOR EACH ROW EXECUTE FUNCTION realtime_invoices_changed();
DO $$ BEGIN
 EXECUTE format('ALTER FUNCTION %I.realtime_invoices_changed() SET search_path = %I, pg_catalog, pg_temp',current_schema(),current_schema());
END $$;
