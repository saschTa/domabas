ALTER TABLE document_files DROP CONSTRAINT document_files_location_check;
ALTER TABLE document_files ADD CONSTRAINT document_files_location_check
    CHECK (location IN ('staged', 'final', 'unlocked'));
