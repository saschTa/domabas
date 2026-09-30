ALTER TABLE document_ai_jobs
 ADD COLUMN invoice_classifier_version integer NOT NULL DEFAULT 0 CHECK(invoice_classifier_version IN (0,1)),
 ADD COLUMN invoice_decision text CHECK(invoice_decision IN ('invoice','not_invoice','uncertain')),
 ADD COLUMN invoice_decision_reason text CHECK(invoice_decision_reason IN ('invoice','credit_note','quotation','order','delivery_note','bank_statement','forwarding_email','other_document','insufficient_text','mixed_document','ambiguous','incomplete_coverage','prior_invoice')),
 ADD COLUMN invoice_classification_pass integer NOT NULL DEFAULT 0 CHECK(invoice_classification_pass BETWEEN 0 AND 2),
 ADD COLUMN invoice_input_characters integer NOT NULL DEFAULT 0 CHECK(invoice_input_characters>=0),
 ADD COLUMN invoice_source_characters integer NOT NULL DEFAULT 0 CHECK(invoice_source_characters>=invoice_input_characters),
 ADD CONSTRAINT invoice_classification_complete CHECK(
   (invoice_decision IS NULL AND invoice_decision_reason IS NULL AND invoice_classification_pass=0) OR
   (invoice_decision IS NOT NULL AND invoice_decision_reason IS NOT NULL AND invoice_classification_pass>0 AND invoice_classifier_version=1)
 );
ALTER TABLE document_ai_jobs ALTER COLUMN invoice_classifier_version SET DEFAULT 1;
