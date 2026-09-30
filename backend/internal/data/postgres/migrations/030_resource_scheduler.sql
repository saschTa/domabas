CREATE TABLE scheduler_settings (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision > 0),
 ollama_queue_size integer NOT NULL DEFAULT 128 CHECK(ollama_queue_size >= 2),
 initialized boolean NOT NULL DEFAULT false
);
INSERT INTO scheduler_settings DEFAULT VALUES;
CREATE TABLE scheduler_resources (
 id text PRIMARY KEY,
 label text NOT NULL,
 origin text NOT NULL DEFAULT '',
 concurrency_limit integer NOT NULL CHECK(concurrency_limit BETWEEN 1 AND 256)
);
INSERT INTO scheduler_resources(id,label,concurrency_limit) VALUES ('worker','Workers',10),('ollama','Ollama',1);
CREATE TABLE scheduler_requests (
 workflow_id text PRIMARY KEY,
 pipeline text NOT NULL CHECK(pipeline IN ('document_ingestion','document_ai','chat','email','paperless')),
 sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 state text NOT NULL DEFAULT 'waiting' CHECK(state IN ('waiting','active','released')),
 blocks_admission boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 admitted_at timestamptz,
 released_at timestamptz
);
CREATE INDEX scheduler_requests_waiting_idx ON scheduler_requests(sequence) WHERE state='waiting';
CREATE INDEX scheduler_requests_active_idx ON scheduler_requests(workflow_id) WHERE state='active';
CREATE TABLE scheduler_request_resources (
 workflow_id text NOT NULL REFERENCES scheduler_requests(workflow_id) ON DELETE CASCADE,
 resource_id text NOT NULL REFERENCES scheduler_resources(id),
 PRIMARY KEY(workflow_id,resource_id)
);
CREATE INDEX scheduler_resource_usage_idx ON scheduler_request_resources(resource_id,workflow_id);

CREATE VIEW scheduler_waiting_requests AS
WITH active_usage AS (
 SELECT rr.resource_id,count(*) AS active
 FROM scheduler_requests q JOIN scheduler_request_resources rr ON rr.workflow_id=q.workflow_id
 WHERE q.state='active' GROUP BY rr.resource_id
)
SELECT q.workflow_id,q.sequence,
 NOT EXISTS(SELECT 1 FROM scheduler_requests b WHERE b.state='active' AND b.blocks_admission)
 AND NOT EXISTS(
  SELECT 1 FROM scheduler_request_resources rr
  JOIN scheduler_resources r ON r.id=rr.resource_id
  LEFT JOIN active_usage a ON a.resource_id=r.id
  WHERE rr.workflow_id=q.workflow_id AND COALESCE(a.active,0)>=r.concurrency_limit
 ) AS feasible
FROM scheduler_requests q WHERE q.state='waiting';
