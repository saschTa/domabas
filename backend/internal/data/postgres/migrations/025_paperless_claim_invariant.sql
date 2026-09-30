ALTER TABLE paperless_items
    DROP CONSTRAINT paperless_items_claim_complete,
    ADD CONSTRAINT paperless_items_claim_complete CHECK (
        (claim_token IS NULL AND claim_deadline IS NULL AND claim_recover_after IS NULL)
        OR (claim_token IS NOT NULL AND claim_deadline IS NOT NULL AND claim_recover_after IS NOT NULL AND claim_recover_after > claim_deadline)
    );
