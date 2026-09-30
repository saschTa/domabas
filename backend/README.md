# Domabas backend

The Go backend serves the API, checks permissions, stores application data in
PostgreSQL and runs Temporal workers for background jobs. Document parsing and
text recognition run in a separate private processor service.

This guide is for developing and checking the backend. To host the complete
application, use the [Compose guide](../docs/development/compose.md). For code
structure, start with [backend architecture](../docs/arch/backend/index.md).

## Start development

Install the tools listed in the [development guide](../docs/development/index.md).
This checkout uses Go **1.27.1**, PostgreSQL **18.6** with pgvector **0.8.6**,
Temporal Server **1.32.0** and Temporal Go SDK **1.49.0**. Version sources are
[`go.mod`](go.mod), [`.tool-versions`](../.tool-versions) and
[`compose.yaml`](../compose.yaml).

Run from the repository root:

```sh
task dev
```

This starts the required infrastructure, Go hot reload and Flutter. To work on
the backend alone, start infrastructure from the root, then run Go from here:

```sh
task infra:up
cd backend
go run ./cmd/server
```

The server applies pending database migrations before it starts serving. Use
`go tool air` instead of `go run ./cmd/server` for automatic rebuilds. With the
native macOS MLX runtime, `task infra:up` stays in the foreground; run the backend
in a second terminal. See [Ollama runtime selection](../docs/development/compose.md#select-the-development-ollama-runtime).

Stop a packaged backend before starting a native backend on the same task queue:
`docker compose stop web backend` from the root leaves infrastructure running.
`task infra:down` stops infrastructure while retaining its data.

## Configuration

[`backend/.env`](.env) contains checked-in local development defaults. Exported
environment variables override them. `DOMABAS_ENV_FILE` selects another file;
set it to an empty string to use only the process environment. Keep deployment
secrets out of tracked files.

| Setting | Purpose and default |
| --- | --- |
| `DATABASE_URL` | Required PostgreSQL connection string. The development file uses port `54329`. |
| `HTTP_ADDR` | HTTP listen address; `127.0.0.1:8080`. |
| `CORS_ORIGINS` | Exact allowed browser origins; local development uses port `7357`. |
| `TEMPORAL_ADDRESS` | Temporal endpoint; `127.0.0.1:7233`. |
| `TEMPORAL_NAMESPACE` | Registered workflow namespace; `domabas`. |
| `TEMPORAL_TASK_QUEUE` | Base worker queue; `domabas-documents`. |
| `OLLAMA_MAX_QUEUE` | Ollama queue budget; `128`. Keep it consistent on Ollama, backend replicas and the processor. |
| `TEST_DATABASE_URL` | Explicit database connection for directly invoked database tests. |

Administrators set background capacity in **Admin settings → Workload limits**.
Worker capacity defaults to ten jobs, shared Ollama capacity to one, and each
external provider origin to two. Ollama background capacity cannot exceed half
its configured queue budget. The old `DOCUMENT_INGESTION_CONCURRENCY` and
`DOCUMENT_AI_CONCURRENCY` settings no longer control admission. See
[resource scheduling](../docs/arch/backend/resource-scheduler.md).

Compose gives this service a 2 GiB memory ceiling and a 1536 MiB Go soft target.
See the [resource guide](../docs/development/resources.md) for the complete
stack, native-process settings and memory diagnosis.

## Check changes

Run these commands from the repository root:

| Command | What it checks |
| --- | --- |
| `task test:backend` | Go unit tests and architecture rules, with the race detector. |
| `go -C backend vet ./...` | Go static analysis. |
| `go -C backend build ./...` | Compilation of backend packages. |
| `task test:integration` | PostgreSQL repositories against isolated schemas. |
| `task test:temporal` | Real Temporal workers, queues and recovery. |
| `task test:api-e2e` | The compiled API process, its contract and persistence. |
| `task check` | Repository analysis, generated-code consistency and fast tests. |

Database and Temporal tests need running services. The root harness configures
unique disposable schemas and task queues, and removes only its own test data.
When invoking tagged Go tests directly, explicitly export `TEST_DATABASE_URL`;
they do not fall back to `.env`. The login must be able to create and drop
schemas. See [testing and CI](../docs/development/testing.md) for setup and the
full test matrix.

## Change the API or database

Edit the [OpenAPI contract](../contracts/backend/openapi.yaml) first, then run
`task generate` from the root. Commit both the generated Go server/types and Dart
client. Generated sources are checked in so normal builds need no generation.

For a database change, add a new numbered SQL migration. Never edit an applied
migration: startup verifies its checksum and migration order. Pending migrations
run in a transaction under a PostgreSQL advisory lock. `task db:migrate` applies
them without starting the API.

`task generate:db` regenerates Jet models and table definitions from an isolated
migrated schema; `task generate:db:check` checks for drift. Both need PostgreSQL
and schema-creation rights. See [database boundaries](../docs/arch/backend/boundaries.md)
and [persistence rules](../docs/arch/backend/persistence.md).

## Health and administration

`/healthz` reports whether the process is alive. `/readyz` also checks PostgreSQL,
Temporal, its namespace and local workers. Shutdown drains HTTP and activities
before closing the Temporal client and database. The
[lifecycle guide](../docs/arch/backend/boundaries.md) explains failure handling.

On a new, empty installation, the first registration becomes system
administrator. If a retained installation has no administrator, explicitly choose
an existing user with `task db:bootstrap-admin -- --user-id USER_UUID`. System
administration does not grant access to other people's libraries. See
[identity and access](../docs/arch/backend/identity.md).

## Inspect a document workflow

The diagnostic workflow reads a document through the real service and repository.
From `backend/`, run:

```sh
go run ./cmd/workflow --account-id ACCOUNT_UUID --document-id DOCUMENT_UUID
```

For a packaged deployment, run from the root:

```sh
docker compose exec backend /app/workflow --account-id ACCOUNT_UUID --document-id DOCUMENT_UUID
```

The `domabas.DocumentMetadata.v2` workflow returns only `id` and `createdAt` as
JSON; private titles and descriptions stay out of workflow history. Logs go to
stderr. Missing documents do not retry; transient reads allow three attempts in
total.

Use `--enqueue-only --workflow-id UNIQUE_ID --timeout 2m` to submit without
waiting. Later, use `--wait-workflow-id UNIQUE_ID --run-id RUN_ID --timeout 2m`
without the account/document flags to retrieve that run. Submission sets a remote
execution timeout as well as a local wait timeout. Interrupting a synchronous
invocation terminates only the exact run it created; enqueue-only submissions
continue, and waiting for an existing run does not terminate it.
