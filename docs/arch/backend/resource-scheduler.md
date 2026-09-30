# Shared background resource scheduler

One scheduler owns admission policy for document ingestion, document AI, private
chat, email retrieval, Paperless imports and document thumbnails across all backend instances.
Existing transactional outboxes still own accepted work and Temporal still runs
it. Domain dispatchers ask the shared scheduler for admission in the transaction
that records execution ownership. They continue to deliver and reconcile their
existing workflow protocols. Activities do not poll the ingestion backlog or
cancel model requests to make room for new ingestion.

## Resource requirements

Every admitted job holds one worker permit. This counts active background jobs,
not operating-system threads or CPU cores. Other permits depend on the accepted
job configuration:

| Pipeline | Additional resource |
| --- | --- |
| Document ingestion and full reindex | Ollama for embeddings |
| Document AI | Its accepted provider when LLM extraction is enabled; none for structured invoice extraction alone |
| Private chat | Its accepted provider |
| Email retrieval | None; accepted originals enter document ingestion separately |
| Paperless imports | None; accepted originals enter document ingestion separately |
| Document thumbnails | None; first-page/image rendering uses CPU only |

Retained combined ingestion can need both Ollama and an external provider.
Reservations cover the whole job, including transitions and provider retries.
This is deliberately conservative: no activity holds one resource while waiting
for another. Paperless source retrieval parallelism remains an independent
source-protection setting and can involve several file transfers per active job.

Internal Ollama and an OpenAI-compatible endpoint at its configured origin share
one resource. External resources are grouped by canonical scheme, host and port,
so models, credentials and URL paths at the same origin share capacity. The
scheduler stores a safe origin label and a stable hash identifier, never secrets.
Different origins receive independent editable limits.

Ollama background capacity cannot exceed half `OLLAMA_MAX_QUEUE`, rounded down,
and all resource limits are bounded to 256 active jobs. The operator must keep
that value aligned with Ollama's actual queue setting. Queue sizes below two are
invalid. Ollama's queue size is not the same as GPU execution parallelism; admins
should choose a smaller job limit when models or hardware require it. Semantic
search and readiness probes are short foreground requests and use the remaining
headroom. Unrelated clients of the same runtime are outside Domabas admission.

## Durable admission and fairness

`scheduler_requests` retains stable workflow identities and a monotonic waiting
order. `scheduler_request_resources` stores the complete typed resource vector.
`scheduler_resources` holds installation limits; `scheduler_settings` holds an
optimistic revision and startup ownership-initialization state.

The submitting service checks current authority when required. Its admission
command takes the domain's coordination and candidate locks, followed by the
scheduler singleton lock. The scheduler never takes foreign domain locks. It inspects retained execution ledgers using
ordinary MVCC reads. All required permits are granted atomically only when the
complete vector fits and no older feasible waiter exists. A job blocked on
Ollama does not block an eligible worker-only import. Existing bounded dispatcher
polling delivers grants; waiting jobs occupy no Temporal activity slots.

A denied request stays durable. Cancellation or supersession removes a waiter
only when its source job is no longer eligible. Active reservations are released
only after the existing domain reconciliation proves execution closure. Missing
history, a process restart, an expired delivery lease, or a terminal UI status
alone never releases possibly running work. The domain execution ledger and
scheduler grant commit together, so there is no new database/Temporal dual write.
Retained records have no destructive entity foreign key that could erase active
ownership. A lower limit blocks new admission until running work drains; it never
cancels a running request.

Startup reconstructs reservations for retained unclosed executions before any
new dispatcher starts. Existing workflow names, payloads and deterministic
command sequences remain unchanged. Upgrades require coordinated replacement of
old backend workers: binaries using the former admission policy cannot enforce
the new shared budget. Per-pipeline concurrency environment settings no longer
control scheduler admission. Optional legacy scheduling response fields are
omitted; workload settings are the authoritative view.

Document job and current-configuration provider requirements are typed columns.
A capture trigger projects the immutable configuration snapshot at the write
boundary, including the existing automatic downstream-publication trigger.
Startup decodes retained snapshots only for ownership reconstruction. Normal
scheduler queries use relational resource rows and typed provider fields.

## Administration and execution bounds

`system:workloads:manage` authorizes the workload settings API and UI independently
of namespace ownership. Both the HTTP guard and database transaction recheck
authority using one nonlocking identity/session snapshot. GET uses a read-only
repeatable-read transaction and returns limits, maximums, reserved active counts
and current pipeline requirements. It takes no row or advisory locks and performs
no reconciliation or resource registration. Counts exclude execution closures
using the same predicate as mutation-time reconciliation; missing closure evidence
continues to consume capacity.

A configured external origin without a stored resource appears with its stable
ID, normalized origin label and default limit of two. Pipelines sharing an origin
share this projection. GET does not change the settings revision or resource rows.
PUT retains the scheduler singleton lock and checks the submitted revision before
registering projected resources. It validates the complete unique resource set
against the 256-resource cap and rejects unknown IDs; a provider removed from
configuration before save does not become an arbitrary new resource. Stored limits
use the settings revision, while pipeline definitions follow their separately
revisioned document/chat configuration.

PUT requires the current stored revision; stale edits conflict.
Provider resources discovered by new accepted work also advance the revision.
Counts include starting and draining jobs, so they can temporarily exceed a newly
lowered limit. Changing limits does not reindex documents or restart pipelines.

Limit edits validate resource metadata under the scheduler singleton lock and
read active counts once for the response. They do not reconcile or lock request
rows; admission remains responsible for releasing proven closed executions and
removing obsolete waiters. Both settings reads and writes disable JIT within
their transaction. Closed AI workflow lookups use a partial index so active
counts and admission do not repeatedly scan retained AI job history.

Workers support the maximum configurable job count; the shared scheduler, rather
than per-worker slot counts, provides the deployment-wide limit. Document model
requests retain cancellable unbounded transport waits inside heartbeat-monitored
activities. Chat provider calls allow 30 minutes, within the existing 24-hour
activity/workflow bound, and retain renewable execution ownership. User
cancellation, deletion, lost authority and service shutdown still fence and drain
work normally.

## Retained ownership diagnostics

If an old combined ingestion execution has lost its configuration snapshot,
startup records its known worker and Ollama requirements and sets
`blocks_admission`. The backend can start and reconcile that execution, but
new jobs remain queued until closure is proven. Guessing an external provider
would risk admitting work onto an already occupied resource. Inspect these
exceptional retained owners with this read-only query in the application schema:

```sql
SELECT workflow_id, pipeline, admitted_at
FROM scheduler_requests
WHERE state = 'active' AND blocks_admission
ORDER BY sequence;
```

Use the retained workflow identity to inspect its actual Temporal execution.
Normal reconciliation removes the barrier once the domain execution ledger
proves closure. Do not clear the barrier or edit reservations merely because a
workflow is absent from a short history window or a job looks finished in the UI.

The `scheduler_waiting_requests` view provides a current resource-feasibility
hint for bounded candidate discovery. Provider-dependent pipelines prioritize
known feasible waiters, then previously unseen jobs, then known blocked waiters.
This prevents a page of jobs for one saturated provider from hiding another
provider indefinitely. The view takes no locks and grants no capacity; the
atomic scheduler admission check remains authoritative.

Document admission submits at most 20 candidates in one transaction and grants
at most one. It tries the scheduler singleton with SKIP LOCKED, yielding when
another scheduler transaction owns it. A yielded pass grants no new capacity;
accepted jobs remain available to a later poll. An acquired pass reconciles
execution closure once, then preserves the same resource and oldest-feasible
checks for each candidate. Other single-reservation callers retain their
blocking scheduler lock. Admission uses transaction-local jit=off to avoid
repeated compilation costs for short queue queries.

AI dispatchers serialize on a separate schema-specific document-ai-admission
advisory lock. Accepted AI snapshots, job locks and scheduler reservations do
not require the publication/configuration barrier. Pending AI lease claims and
execution resolution likewise use their row locks and exact ownership predicates.
Ingestion keeps its existing generation and reindex coordination, but yields
instead of waiting for a busy scheduler. A scheduler grant and its domain
execution record still commit or roll back together.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
