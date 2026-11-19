# Backend boundaries and lifecycle

Each domain groups its models, interfaces and services in the core. Domain data sources own Jet query builders and pgx I/O; repositories convert generated database records and domain data aggregates into core values. HTTP types stay in presentation. Bootstrap wires native job steps to domain service ports. The jobs adapter owns checkpoints and worker election. Core models, interfaces and services depend on neither adapter role. See [domain structure](domain-structure.md) for folder and cross-domain rules.

Each domain's bootstrap container constructs its repository, service, and
activities using shared resources borrowed from root bootstrap. Root connects
consumers through application services and owns the PostgreSQL source and worker lifecycle. Containers keep repositories and activities private.
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
worker startup continue only after migration commit. Nontransactional SQL and
down-migration commands are outside this runner's scope.

## Worker lifetime

Root owns the native Go worker. See [native jobs](native-jobs.md) for election, restart and shutdown.
