# Temporal and worker lifetime

Temporal coordinates background work that should survive a backend restart.
PostgreSQL keeps the application's job records and pending delivery requests;
Temporal keeps the workflow history used to resume execution. Both are needed.

## Workflow, activity and task queue

A **workflow** is the recorded sequence of steps. An **activity** performs I/O:
reading a document, calling a model, contacting IMAP or committing a result.
A **task queue** routes that work to a compatible worker. The Go backend embeds
workers for ingestion, document AI, thumbnails, email, Paperless and chat. There
is no separate Domabas worker service to start.

The configured `TEMPORAL_TASK_QUEUE` is the base ingestion queue. Other worker
queues add `-ai`, `-thumbnail`, `-email`, `-paperless` or `-chat`. Tests give each
database schema its own base queue, so a worker cannot accidentally process
another test's records. [Root bootstrap](../../../backend/internal/bootstrap/backend_app.go)
constructs and supervises these workers.

Temporal rebuilds workflow state by replaying recorded events. Workflow code must
therefore make the same decisions for the same history. Database access, files,
network requests and ordinary wall-clock reads belong outside deterministic
workflow code. This follows Temporal's
[workflow model](https://docs.temporal.io/workflows).

Definitions live in `domain/<domain>/workflows/*.workflow.go`. Activities and
dispatchers live in `data/<domain>/temporal`. Stable registered names, payload
fields, version markers and command order form a compatibility contract for
histories already stored by Temporal. Moving Go code must preserve that contract.
The core models, interfaces and services do not depend on the workflow SDK.

## How a job reaches a worker

1. A service accepts work and commits the job and its delivery intent together.
2. A dispatcher asks the [resource scheduler](resource-scheduler.md) to reserve
   the job's complete worker and provider requirements.
3. The dispatcher starts the workflow with a stable identity and records the
   returned execution identity. An uncertain start is checked against Temporal
   before another start is attempted.
4. Activities call injected service ports, record bounded progress and apply
   writes only while they still own the accepted job or document generation.
5. Reconciliation compares retained execution ownership with Temporal's state.
   It releases capacity only after execution closure is established safely.

This is not a promise that an activity runs exactly once. A network failure can
hide a successful completion, and retries can repeat an activity. Stable request
identities, idempotent operations, transaction checks and ownership tokens make
those retries safe. See [background job rules](background-jobs.md) and the
individual pipeline guides for their deadlines and cancellation behavior.

Workflows and heartbeats carry durable identities and bounded progress rather
than document text or credentials. Activities retrieve private content from
application storage when needed. Retained history is still operational data and
belongs on the private infrastructure network.

## Periodic discovery and retention

Domabas currently discovers due work using backend loops and database timestamps,
rather than Temporal Schedule objects. For example, ingestion delivery polls
roughly every two seconds and reconciliation every fifteen seconds. Email due
checks and thumbnail discovery create durable jobs; they do not leave the work
owned by a timer or a browser page.

The namespace initializer creates a new namespace with 72-hour history retention.
Retained namespaces keep their settings. Delivery retry windows are bounded
against retention. Some document model waits remain cancellable without a fixed
execution timeout, so elapsed time alone cannot prove that they stopped.
If closed history disappears before reconciliation can observe it, a reservation
may remain held. Investigate the retained identity instead of clearing it merely
to make the queue move. See [scheduler diagnostics](resource-scheduler.md#retained-ownership-diagnostics).

## Startup, readiness and shutdown

Startup prepares the database, connects to Temporal, checks the namespace, starts
workers and starts dispatchers. Readiness checks workers and dispatchers as well
as dependency connectivity. A fatal worker error reaches the backend supervisor;
a process that cannot serve background work must not continue reporting ready.

Startup has a deadline. Running activities belong to the application's lifetime,
so expiry or cancellation of the startup context cannot stop them later. During
shutdown, dispatchers stop and workers drain their activities before the Temporal
client and PostgreSQL pool close. An SDK worker-stop timeout is not a substitute
for that drain barrier. [Lifecycle tests](../../../backend/internal/bootstrap/temporal_worker_lifecycle_test.go)
cover this ordering.

The [Temporal UI](../../development/compose.md) is useful for execution-level
diagnostics. User-facing progress comes from the application's job records, which
also retain the information needed for cancellation and reconciliation.
