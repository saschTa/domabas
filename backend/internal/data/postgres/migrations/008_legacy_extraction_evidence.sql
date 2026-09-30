UPDATE document_processing p SET requires_extraction=false
FROM documents d WHERE d.id=p.document_id AND d.account_id=p.account_id
AND p.reason='legacy' AND d.ocr_manual_text IS NOT NULL;
UPDATE document_processing_jobs j SET requires_extraction=false
FROM documents d WHERE d.id=j.document_id AND d.account_id=j.account_id
AND j.reason='legacy' AND d.ocr_manual_text IS NOT NULL;
