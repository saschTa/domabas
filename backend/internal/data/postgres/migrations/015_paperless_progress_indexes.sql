CREATE INDEX paperless_items_pending ON paperless_items(run_id,source_id) WHERE status='pending';
CREATE INDEX paperless_items_outcomes ON paperless_items(run_id,source_id DESC) WHERE status<>'pending';
