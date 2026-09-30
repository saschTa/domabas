ALTER TABLE document_uploads DROP CONSTRAINT document_uploads_size_check,
 ADD CONSTRAINT document_uploads_size_check CHECK(size BETWEEN 1 AND 104857600);
ALTER TABLE document_files DROP CONSTRAINT document_files_size_check,
 ADD CONSTRAINT document_files_size_check CHECK(size BETWEEN 1 AND 104857600);
ALTER TABLE documents DROP CONSTRAINT documents_ocr_machine_text_check,
 ADD CONSTRAINT documents_ocr_machine_text_check CHECK(octet_length(ocr_machine_text)<=2097152),
 DROP CONSTRAINT documents_ocr_manual_text_check,
 ADD CONSTRAINT documents_ocr_manual_text_check CHECK(octet_length(ocr_manual_text)<=2097152);
ALTER TABLE document_chunks DROP CONSTRAINT document_chunks_position_check,
 ADD CONSTRAINT document_chunks_position_check CHECK(position BETWEEN 0 AND 2047);
