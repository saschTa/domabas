# Paperless-ngx import

The deterministic definition is
`domain/paperless/workflows/paperless_import.workflow.go`.
`PaperlessImportActivities` and `PaperlessImportDispatcher` live in
`data/paperless/temporal`, with injected service ports. Explicit registration
keeps `domabas.PaperlessImport.v1` and its activity names stable.

Paperless import is a durable Temporal pipeline following the
[background job guidelines](background-jobs.md). Settings queues a job and reads
its persisted progress when private WebSocket notifications arrive, without
polling. Leaving the screen or signing out does not drive or stop
the work. Jobs & pipeline also shows the Paperless pipeline and the user's
paginated imports in its shared chronological list, with pipeline/status filters
and the common job detail page. Details show persisted counters, paginated per-file
outcomes and links to accepted documents. Imports completed with failed files
appear as partially completed. Accepted originals continue as separate document
ingestion jobs. The namespace claim `paperless:import` is required alongside
document read and upload permissions. Jobs and source credentials belong to their
creator and destination library.

History accepts optional status and active-only filters before its keyset page
limit. `partial` selects succeeded runs with failed items; `succeeded` excludes
these runs. Counts describe the entire authorized history. Cursors bind both
filters as well as owner, library and page size.

Each user opens Settings → Paperless import, enters their own Paperless server
base URL and API token from Paperless's My Profile, and starts an import into the
displayed library. A path prefix is supported. No server allowlist, administrator
setup, Paperless password or encryption-key entry is required. The backend must
be able to reach the source; `localhost` refers to the backend host or container.
Connections are submitted with each job. Tokens never return to the UI and are
not saved in browser storage.

Creation commits a request UUID, source URL, encrypted API token, background
credential revision and queue intent together. Reusing the same request UUID and
connection details returns the existing job. One active job per user/library and
a bounded installation queue prevent accidental resubmission. Tokens use
AES-256-GCM with job, namespace and owner as associated data, and are cleared on
terminal outcomes. They never enter Temporal history or API responses.

A database coordination row protects admission of up to ten imports across all
Go instances. Admitted runs retain capacity until execution closure, including
cancelled or failed runs. A persisted next-check time rotates delivery and
reconciliation across admitted imports. A separate schema-specific queue runs up
to ten activities at a time; each import still processes its steps sequentially,
with a 100 ms pause between steps.

During retrieval, one step reserves a batch of different source documents and
retrieves them concurrently. System administrators configure installation-wide
retrieval concurrency in Settings, from 1 to 10, with a default of 1.
`GET` and `PUT /api/v1/system/paperless-import` require
`system:paperless:manage` at HTTP and service boundaries. This permission is
independent of namespace import access. Settings use their own optimistic
revision and never trigger document reindexing. A lower limit applies to new
claims while existing retrievals drain.

The admission row serializes batch reservation across all runs and replicas.
Each pending item receives a claim token, a 60-second operation deadline and a
recovery deadline 120 seconds after reservation. All retrieval and staging work
uses the operation deadline. A crashed worker's capacity is recovered only after
the additional drain grace. Token and deadline checks fence upload acceptance and
outcome writes; stale workers cannot overwrite a replacement claim. Normal
completion releases capacity after retrieval I/O and cleanup return. A batch
cancels and joins sibling calls before releasing claims on failure; cancellation
is checked once per second and remains authoritative at acceptance. A full
installation or an already claimed item is ordinary waiting and does not consume
activity retries or complete the run. Database locks never span source or file I/O.

The existing workflow and activity registration names, payloads and command order
remain unchanged. Replace all old backend workers before relying on the global
retrieval limit: old binaries do not reserve item claims. Retained executions can
resume on new workers without a workflow history migration.

The dispatcher reconciles the
stable workflow identity, rejects reuse, bounds ambiguous-start retries to less
than Temporal retention and retains admission until execution closure. Discovery
and each document have independent persisted checkpoints. Activities have a
60-second operation deadline, a 90-second execution limit and four attempts with
exponential backoff. Workflows continue as new after 100 steps and have a seven-day
execution limit. Activities load only the run state needed for their next step;
they do not recalculate all progress counters and outcome history for every file.
Partial indexes select the next pending item and recent completed outcomes.
Progress counters are read when a user requests the job's current status.

The adapter uses Paperless API version 9, token authentication, ascending-ID
pagination and explicit original downloads. It never follows redirects or
upstream next URLs. User-entered base URLs reject credentials, queries, fragments,
escaped paths and invalid ports. Proxies are disabled and TLS certificates are
verified. Destination checks apply to every resolved dial address. Public,
private LAN and loopback destinations support self-hosted sources; link-local,
metadata, unspecified and multicast destinations are blocked. This deliberately
allows authenticated importers to connect to a Paperless source on the backend's
network; operators of a publicly shared installation should also enforce their
intended outbound network policy. Each source document's metadata requests are
sequential, while different documents can overlap. The
shared HTTP adapter starts requests at least 100 ms apart per Go process,
including requests from different imports. JSON is limited to 1 MiB and originals
to Domabas's 100 MiB limit. Discovery processes
100 documents per page without a fixed library-size cap and rejects inconsistent
page totals or ordering. Source edits
during discovery should be avoided.

Titles, dates, normalized tags and correspondents map to document metadata.
Descriptions retain the source link, document type and archive serial number.
Originals pass through the existing upload reservation, storage validation,
namespace byte-hash uniqueness and transactional processing outbox. When source
metadata fails Domabas validation, the original still imports with the title
`Paperless document <source ID>`, kind `document` (or `email` for an email original),
and only the full source link in its description. Source tags, correspondent,
date, document type and archive serial number are omitted together in this
fallback. Valid metadata keeps its existing mapping. Oversized or invalid
discovery titles use the generated title so discovery can continue. Transport,
authorization, source identity and original-file errors still fail normally.
Previously failed items can be retried by starting another import; completed
job history is unchanged and existing originals are detected as duplicates.
Notes, custom fields,
permissions, versions and corrected OCR are not migrated; Domabas extracts and
indexes text from the original. A retry after a lost acceptance receipt can report
an already accepted file as a duplicate. Existing documents retain their metadata.

Discovery rechecks membership, claims and the initiating credential revision.
Document staging and acceptance independently check the live run and cancellation
flag under the run → document lock order. Identity and claims come from one
joined query without identity row locks. Foreground requests also validate their
session; background work uses retained credential consent. An operation already
authorized may finish after concurrent revocation, and every later transaction
checks again. Run, item-claim and admission locks retain cancellation and worker
ownership guarantees. Settings, history and outcome reads use read-only
repeatable-read snapshots with no explicit row or advisory locks. No network or filesystem I/O
holds those database locks. Cancellation fences new acceptance; accepted files
remain. Outcome persistence is idempotent by job/source ID. UI results distinguish
imported, duplicate and failed files. Import history and completed outcomes each
use opaque keyset cursors, defaulting to 20 records with a maximum of 100 per
response. Run cursors order creation time and ID descending; outcome cursors
order source ID descending. Cursors bind the operation, owner, library, page size
and run where applicable. Every page rechecks session and claims.

The outcome endpoint accepts an optional `status` filter (`failed`, `imported`,
or `duplicate`), applied before the page limit and bound into its cursor. Settings
and job details share result filter chips, so failed files remain reachable even
when newer successful results occupy the first page. Switching filters resets
pagination and cancels/fences earlier requests. Refresh and continuation retain
the selected filter; background updates preserve loaded history. Failed result
rows include the source ID, title, readable failure and selectable error code.

Import lists omit embedded outcomes. The UI reads
`GET /api/v1/paperless-import/runs/{runId}/outcomes` when results are opened,
with separate continuation and retry state. Legacy single-run responses retain
their bounded first-100 preview for existing clients. All persisted results are
reachable through the outcome endpoint. Cursors describe live positions, not
a cross-request snapshot; refresh the first page to see newly completed results.

## Automatic credential encryption

Temporal activities must recover the API token after sign-out or a backend
restart. Domabas therefore encrypts each active job's token instead of storing
it as plaintext. A hash would not allow the worker to authenticate to Paperless.
Encryption protects tokens in a database-only backup; it does not protect against
an attacker who controls the running backend and its key files.

On first startup, Domabas generates a random 32-byte key and writes a private
file at `DOCUMENT_STORAGE_ROOT/.secrets/paperless.key`. Later startups reuse it.
`PAPERLESS_CREDENTIAL_KEY_FILE` optionally changes that path. Complete temporary
files are synced and published exclusively so concurrent startup cannot overwrite
another process's key or read partially written key material. The database's
admission lock coordinates startup validation with import creation. Invalid,
insecure or missing key files with active encrypted credentials fail startup;
they are not silently replaced. A retained token must decrypt with the selected
key before workers start.

Compose stores the key in its retained `credential_keys` volume at
`/var/lib/domabas/secrets/paperless.key`. Keep the key with installation backups,
and share the same key file between replicas using the same database. Ordinary
shutdown preserves it. The existing `PAPERLESS_CREDENTIAL_KEY` environment
override remains supported for deployments that already supply a base64-encoded
32-byte key. Such deployments must retain their existing override while jobs
are active. New installations need neither environment variable.

The old `PAPERLESS_SERVERS` setting is no longer used. Source addresses and tokens
are entered per user in Settings. HTTP sources remain supported for trusted
networks, with an unencrypted-connection notice in the form.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
