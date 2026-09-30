# Backend dependency injection

Root `bootstrap/backend_app.go` owns shared resources and process lifetime. Each domain
assembles concrete dependencies in `bootstrap/<domain>/<domain>_container.go`. Core
models, interfaces and services live together under `domain/<domain>`, while
concrete construction stays outside core. Dependencies are ordinary constructor
arguments; there is no service locator or dependency injection framework. See
[domain structure](domain-structure.md) for the complete layout and import rules.

## Document construction

The `DocumentContainer` borrows the shared PostgreSQL `PostgresDatabase` capability and
a clock. It constructs its document data source, repository, service and Temporal
activities without opening a connection. The source receives only `QueryRow`,
`Begin` and `BeginTx`; it cannot close or migrate the pool through that contract.
The repository accepts a consumer-owned `DocumentSource` port using persistence records.
The service accepts its domain repository port using core values.

| Container operation | Responsibility |
| --- | --- |
| `NewDocumentContainer(ctx, database, authority, options, now)` | Construct document dependencies using borrowed storage, an identity service port, configuration and clock |
| `Service()` | Return the document service for injection into consumers |
| `RegisterWorker(registry, invoices)` | Register ingestion workflows and activities with an injected invoice service port |
| `RegisterAIWorker(registry, invoices)` | Register the separate document AI workflow and activities |
| `RegisterThumbnailWorker(registry)` | Register thumbnail workflow and activities |
| `Close()`, `DrainAI()`, `DrainThumbnails()` | Cancel and drain the resources owned by each worker family |

Root constructs `presentation/document/handlers.DocumentHandler` and injects the service
through the handler's consumer-owned interface. Temporal activities in
`data/document/temporal` receive the same service through their
`DocumentReader` port. Neither consumer receives a repository or container.
Generated HTTP types stay in presentation. Deterministic workflow definitions
and their wire values live in `domain/document/workflows`; core models,
interfaces and services remain independent of the SDK. Workflow files use
`.workflow.go`, and their stable registration names are separate from Go names.

`RegisterWorker` accepts `worker.Registry`, which permits registration without
worker start or stop. It registers workflows and individual activity methods
under explicit versioned names once, with duplicate registration checks enabled.
It does not register the activity struct, whose exported `Close` method is a
lifecycle operation.

## Identity construction

The identity container builds its own data source, repository, bounded Argon2
password adapter, fixed Casbin policy and service. Root injects that service
into identity handlers, the shared authentication guard and consumer-owned feature
authority ports. The evaluator stays with services; data sources have no authority
policy dependency. Services interpret raw identity facts and select claims. Locked
identity mutations compare the complete observed facts before applying commands.
See [service policy and persistence](service-policy-and-persistence.md). Storage is borrowed;
the identity container never closes root resources. See [identity](identity.md)
for session, permission and transaction rules.

## Ownership and shutdown

Root opens and migrates PostgreSQL, opens the Temporal client, creates domain
containers and workers, and passes each activity drain hook to its worker
lifecycle. Root supplies readiness, fatal-error supervision and HTTP
composition. Domain containers do not import sibling containers or construct
another domain's adapters.

The startup context bounds connection, migration and container initialization.
The document container receives it for initialization; activity lifetime belongs
to the running application. Normal shutdown stops HTTP before the workers.
Startup failure, normal close and fatal failure share each worker's stop/drain
owner. Workers stop, activities cancel and drain, then Temporal and PostgreSQL
close. A worker
SDK timeout does not replace the activity drain barrier. See
[boundaries and lifecycle](boundaries.md).

## Collaboration and enforcement

Domains collaborate through injected, consumer-owned service interfaces. Foreign
value models and errors can appear in those interfaces; a foreign concrete
service or repository cannot. Root constructs the provider container first and
injects the needed service into the consumer.

Data repositories and sources can also collaborate through consumer-owned data
ports for joins. They may use foreign data value records or the shared generated
schema, while concrete sibling adapters remain private. Keep a multi-table
operation in one source-owned transaction; do not introduce a global transaction
context or call services inside a transaction to simulate a join. The document
legacy-adoption transaction illustrates this boundary.

Architecture tests enforce layer, owner and role imports, including nested,
aliased, blank and dot imports. They distinguish core models, interfaces and
services, domain data and presentation, and the few shared lifecycle/HTTP
packages. The [domain structure guide](domain-structure.md) documents the exact
collaboration rules and the limits of source-level checks.
