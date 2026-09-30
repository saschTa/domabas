# Durable background jobs

Bulk imports, exports, synchronization, reprocessing and other long-running or
multi-step operations must run as Temporal pipelines. An HTTP request starts a
job and returns its durable identity. A browser or native client may monitor and
cancel that job; it must not drive the work with a loop of per-item requests.
Closing a screen, disconnecting a client or restarting a service must not lose
accepted work or require the user to keep an application open.

## Durable acceptance and retries

Commit the job and its queue intent in the same PostgreSQL transaction. Dispatch
that intent to Temporal with a stable workflow identity. Reconcile ambiguous
starts and retained executions before retrying. A database commit followed by an
uncoordinated Temporal call is not a delivery guarantee. Bound start permits and
the retry horizon relative to Temporal retention; an uncertain old start must
become an explicit failure instead of silently starting the work twice.

Workflows contain deterministic orchestration. Activities perform I/O through
injected consumer-owned ports. Workflow inputs, results, errors and heartbeats
contain durable IDs and bounded progress, never credentials, document contents
or transport objects. Definitions live in the owning domain's
`workflows/*.workflow.go` files. Activities and dispatchers live in that domain's
`data/<domain>/temporal` adapter and receive consumer-owned service ports.
Only workflow packages use the SDK's deterministic `workflow` and `temporal`
APIs inside `domain`; core models, interfaces and services remain independent.
Client, worker and activity APIs stay in data adapters or bootstrap.

Register workflows and individual activity methods under explicit stable names.
Source moves and identifier renames must preserve these names, payload fields,
version markers and workflow commands so retained executions remain replayable.

Every activity must be safe to retry. Persist checkpoints and item outcomes, use
unique constraints or stable operation keys, and fence stale or cancelled work
at the acceptance transaction. Exactly-once external delivery is not assumed.
After an ambiguous acceptance, reconcile stored evidence or deduplicate before
continuing. Failed and skipped items need explicit outcomes; a partial import
must not be presented as complete success.

Set activity, schedule and workflow deadlines and an explicit retry policy.
Document model inference is an explicit exception: the requested unlimited model
wait uses no HTTP, schedule or workflow deadline, a long required Temporal
activity fallback and short heartbeats. Its durable admission and missing-history
ownership rules are documented in [document ingestion](document-ingestion.md).
Retry transient failures with exponential backoff and a bounded attempt count.
Authorization failures, incompatible data and unsupported files need terminal or
per-item outcomes rather than endless retries. Continue as new before workflow
history becomes large. Keep request deadlines shorter than activity retry
eligibility, and drain I/O before releasing shared resources.

## Concurrency and source protection

Bound work across the deployment, not just within one process. Use durable
admission when a source or processor requires serialized work. Retain the slot
until the owned workflow has closed and any outstanding activity has drained.
Pagination, body sizes, memory, files, queue depth and concurrent requests all
need explicit limits. Pace external requests and back off on overload. Do not
parallelize a bulk import simply because the source exposes an HTTP API.

All background pipelines use the [shared resource scheduler](resource-scheduler.md). A durable FIFO order admits the oldest feasible complete resource vector. No activity polls the ingestion backlog or yields a running provider request. Workload limits are administered separately from processing configuration, and the UI explains pipeline resource requirements.

No database lock may span a network request, large file operation or Temporal
call. Lock order, transaction ownership, leases and cancellation fences must be
documented for each pipeline. Keep source originals unchanged unless destructive
source behavior is explicitly part of the feature.

## Authority, credentials and lifecycle

Starting background work grants a specific, bounded consent tied to an owner,
destination, credential revision and required claims. Recheck that authority
before discovery and acceptance. Logout can leave explicit job consent active;
password changes, membership removal, claim revocation and cancellation must
prevent further acceptance. Accepted documents remain ordinary library records.

Encrypt retained source credentials with associated data binding them to their
job and owner. Never include secrets in API responses, logs or Temporal history.
Erase credentials when no longer needed. Restrict outbound destinations and keep
TLS verification, response limits and deadlines in the transport adapter.

Root bootstrap owns clients, workers and dispatchers. Stop dispatching, stop
workers, cancel and join activities, and only then close database and transport
resources. Worker and dispatcher health belong in readiness. Tests use unique
schemas, queues and workflow identities and clean up only their own resources.

## History totals

The document, email and Paperless history pages include bounded grouped totals
for Jobs filter pills. Each source counts the complete history under its existing
read authority, independently of page cursors and selected status or pipeline.
Document totals retain namespace and optional document scope; email totals retain
owner, namespace and optional provider scope; Paperless totals retain owner and
namespace scope. Counts use typed SQL group rows, including retained deleted
source history. Paperless effective status treats a successful run with failed
items as partial completion. No aggregate grants access beyond its history list.

## Required verification

Use mock repositories for domain and presentation decisions, and real
PostgreSQL/Temporal for persistence and workflow behavior. Cover duplicate
delivery, uncertain responses, retries, restart, cancellation, revoked authority,
source overload, owner isolation and cleanup. Add API and UI E2E tests for the
complete start → progress → outcome flow. A passing mock test does not establish
durability. Record executed checks and unavailable environments in the feature
plan.

See [document ingestion](document-ingestion.md), [email ingestion](email-ingestion.md)
and [Paperless import](paperless-import.md) for concrete pipelines.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
