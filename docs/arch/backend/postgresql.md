# PostgreSQL and persistent storage

PostgreSQL stores application records, job checkpoints and concurrency settings. Original documents and encryption keys live on persistent disk. Recover the database and files together.

## Databases and roles

Compose runs PostgreSQL 18 with pgvector 0.8.6. The database initializer uses a provisioning administrator to create the application role and database, apply its password and install pgvector. On a retained volume it checks existing state before creating missing objects. The API connects as the application role.

## Schemas and extensions

The application normally uses its configured connection's current schema.
Disposable tests and database generation create a random schema and set their
connection `search_path` to it. Generated Jet table values omit a fixed schema,
so the same application code works in either case. The migration runner pins the
resolved schema during its transaction and rejects a missing current schema.

A schema is a namespace inside a database; it is not a second server. PostgreSQL's
[schemas documentation](https://www.postgresql.org/docs/current/ddl-schemas.html)
explains the search path. Domabas uses schema isolation for tests, while normal
library isolation uses explicit account and authorization predicates in queries.

The `vector` extension must be version 0.8.6 in `public`. Installing it requires
an administrative connection; migration 029 validates it before creating the
HNSW index. An externally managed database therefore needs this extension
provisioned before the application starts. Migration 013 installs or validates
`pg_trgm` 1.6 in `public` for fuzzy word matching. Test schemas share these
extensions and must never remove them during cleanup.

## Application migrations and queries

The backend embeds numbered SQL files from
[the migrations directory](../../../backend/internal/data/postgres/migrations).
Startup and `task db:migrate` use the same runner. An advisory lock prevents two
processes from applying migrations at once. The `schema_migrations` ledger stores
filenames and SHA-256 checksums. Applied history must exactly match the prefix of
embedded migrations; changed, missing or inserted historical files fail startup.
All pending changes commit together or roll back together.

New schema changes get a new migration. Existing migrations are immutable.
Migrations can hold locks and take time: the pgvector index migration builds its
index inside the startup transaction, rather than online with `CONCURRENTLY`.
Use a coordinated upgrade and allow the startup migration budget. See
[migration boundaries](boundaries.md#http-and-persistence) for the supported
legacy ledger transition and its limits.

The shared `PostgresDataSource` owns a pgx pool, currently capped at ten
connections per backend instance. Domain data sources borrow a database
capability with query and transaction methods, but no close or migration methods.
Repositories map database records into domain values. Jet generates selected
record and table builders; parameterized SQL executes through pgx. SQL also lives
in handwritten adapters where a query needs it. There is no generic repository
framework. See [dependency injection](dependency-injection.md).

Operational data uses typed columns and child tables. Search text uses full-text
indexes; embeddings are stored with their model identity and searched through
pgvector. The [persistence guide](persistence.md) explains the limited immutable
JSON exceptions, and [document search](document-ingestion.md#search-and-metadata-edits)
explains index and pagination behavior.

## Files, keys and recovery

Compose keeps PostgreSQL data, staged uploads, final originals, credential keys,
Tesseract weights and the Nomic GGUF in named volumes. Thumbnail JPEG bytes live
in the application database. Document rows retain file identity; background
cleanup coordinates physical deletion with committed application state.

Email, Paperless and document AI have persistent credential keys. Chat keeps its
own key under the document storage root. These keys decrypt saved provider
credentials and must accompany a database restore. Multiple backend instances
must share the corresponding keys and document storage. A model cache can be
downloaded again; originals and encryption keys cannot be reconstructed that way.

Ordinary shutdown preserves data. The repository does not implement an automated
backup service or claim a tested disaster-recovery procedure. Operators must
arrange consistent database, document and key backups. Development and tests
must not truncate shared tables or remove development volumes. Test cleanup
removes only the randomly named schemas or disposable Compose projects that the
test itself created.
