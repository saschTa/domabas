# Backend boundaries and lifecycle

Each domain groups its models, interfaces and services in the core. Domain data sources own Jet query builders and pgx I/O; repositories convert generated database records and domain data aggregates into core values. HTTP types stay in presentation. Deterministic Temporal definitions and wire values live in the separate domain workflow role; activities and dispatchers live in data adapters. Core models, interfaces and services depend on neither adapter role. See [domain structure](domain-structure.md) for folder and cross-domain rules.

Each domain's bootstrap container constructs its repository, service, and
activities using shared resources borrowed from root bootstrap. Root connects
consumers through application services and owns the PostgreSQL source, Temporal
client, and worker lifecycle. Containers keep repositories and activities private.
See [dependency injection](dependency-injection.md) for consumer-owned interfaces,
service value models, data joins and architecture guards.

## HTTP and persistence

The HTTP adapter checks requests beyond generated DTO decoding. It rejects unknown fields, trailing JSON, null values where they are not allowed, invalid UTF-8 and oversized bodies. Responses expose stable error codes instead of storage details. A composition test connects the real HTTP and application layers to a failing repository to check that boundary.

Domain HTTP modules own request models, validation, handlers, and route group
declarations. Generated routing remains the only endpoint registration source;
shared root composition owns headers, timeouts, and readiness. See
[HTTP presentation](http-presentation.md) for grouping and validation order,
including duplicate fields and noncanonical URLs.

Migrations run inside a transaction with an advisory lock, so simultaneous startup does not apply a migration twice. Applied migrations are not edited. A repeatable-read transaction keeps a document page and its total count consistent while other requests write data.

Migration filenames use a positive three-digit number and lowercase identifier,
such as `002_document_versions.sql`. Duplicate numbers are rejected; gaps are
allowed. The existing database-wide advisory lock `684019283` coordinates old
and new binaries. After acquiring it, the runner resolves `current_schema()`
and pins an exclusive transaction-local search path, so a history table in a
later schema cannot be adopted accidentally. A missing current schema fails.

Applied rows must match an exact prefix of the embedded filenames and SHA-256
checksums. The original two-column ledger has one supported transition: empty
history or the single `001_documents.sql` row, with the original file bytes.
The runner checks the legacy columns, defaults, nullability and primary key,
then adds and fills a non-null checksum column in the migration transaction.
It preserves old application timestamps and document records. Once a checksum
column exists, null or changed checksums are rejected; there is no repeated
adoption path. Legacy adoption establishes future checksum enforcement, but
cannot prove the SQL originally executed or detect arbitrary manual schema edits.

Pending DDL, history writes and legacy changes roll back together on failure.
Cancellation while waiting for the lock or applying SQL fails startup, and
rollback uses a fresh bounded context so a later attempt can retry. HTTP and
Temporal startup continue only after migration commit. Nontransactional SQL and
down-migration commands are outside this runner's scope.

## Temporal

Definitions live in `domain/<domain>/workflows/*.workflow.go`, and activity I/O
and dispatch live in `data/<domain>/temporal`. Explicit registration names,
payload fields, version markers and command ordering form the compatibility
boundary for retained histories; Go type, function and file names may change
without changing that protocol.

The metadata activity returns only the document ID and creation time. Titles, descriptions, database errors and connection details do not enter workflow history. Its document-reader port receives the application service. The document container constructs activities and registers the named workflow and activity method; root bootstrap creates and starts the worker.

Worker startup has a deadline, but the worker and its activities live until application shutdown. Tests cancel the startup context immediately and still require work to finish afterward. Each database test schema has a separate queue, preventing another test's worker from reading the wrong database.

Normal shutdown and fatal worker failure share one stop operation. Readiness fails when shutdown starts. The Temporal SDK's stop signal can precede completed activity work, so the application waits for its own activity drain before closing clients or PostgreSQL connections. This ordering is covered by race tests.

The document container's close hook drains only its activities. Root passes that
hook to the existing worker lifecycle, which also handles failed startup, then
closes the Temporal client and PostgreSQL source after the drain. No startup
context or shared-resource close operation belongs to the domain container.

The diagnostic command bounds both the client wait and remote workflow lifetime. If an invocation stops waiting for a workflow it created, it terminates that exact run using a fresh cleanup context. Waiting for an existing workflow does not give the command ownership of it.
