ALTER TABLE paperless_admission
    ADD COLUMN retrieval_concurrency integer NOT NULL DEFAULT 1 CHECK (retrieval_concurrency BETWEEN 1 AND 10),
    ADD COLUMN settings_revision bigint NOT NULL DEFAULT 1 CHECK (settings_revision > 0);

ALTER TABLE paperless_items
    ADD COLUMN claim_token uuid,
    ADD COLUMN claim_deadline timestamptz,
    ADD COLUMN claim_recover_after timestamptz,
    ADD CONSTRAINT paperless_items_claim_complete CHECK (
        (claim_token IS NULL AND claim_deadline IS NULL AND claim_recover_after IS NULL)
        OR (claim_token IS NOT NULL AND claim_deadline IS NOT NULL AND claim_recover_after > claim_deadline)
    );
CREATE INDEX paperless_items_claims ON paperless_items(claim_recover_after) WHERE claim_token IS NOT NULL;
