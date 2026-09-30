# Backend domain structure

The backend groups handwritten business code by domain inside each boundary.
The current domains are `document`, `identity`, `email`, `invoice`, `paperless`,
`realtime`, `chat` and `scheduler`. A domain can contain several
services or cohesive subpackages; add them when behavior needs them, without
creating empty folders or forwarding packages.

```text
internal/
  domain/<domain>/
    models/                    Core values, errors and validation
    interfaces/                Core repository and capability ports
    services/                  Application use cases
    workflows/                 Deterministic *.workflow.go definitions and wire values
  bootstrap/<domain>/
    <domain>_container.go       Concrete domain construction
  data/<domain>/
    models/                    Persistence aggregates and data errors
    repos/                     Domain mapping and repository-owned source ports
    datasources/               SQL and transaction ownership
    temporal/                  Activities, dispatchers and injected service ports
  data/identity/security/      Argon2 and Casbin adapters
  presentation/<domain>/
    models/                    HTTP input/output values and model validation
    handlers/                  HTTP operations and consumer-owned service ports
    routes/                    One Register function, predecoding and middleware
  data/postgres/               Shared pool owner and migration lifecycle
    generated/                 Generated relational schema rows/builders
    migrations/                Immutable embedded migrations
  data/temporal/               Shared Temporal client and readiness
  presentation/httpapi/        Root HTTP composition and health/readiness
    contract/                  Generated public contract
    routing/                   Shared generated route grouping
    transport/                 Shared JSON, errors and injected security guards
```

Package names follow their directories. Import aliases such as `documentmodels`
or `identityhandlers` identify the owner when role names would collide. Keep
handwritten value definitions in `*.model.go`; a persistence aggregate can use
`identity.pg.model.go`. Keep validation methods with their receiver types in the
same package. Generated files retain generator-managed names. A nested models
package must stay independent of services and infrastructure.

Handwritten type names identify their domain or technology and purpose without
relying on a folder: `DocumentService`, `InvoiceDataSource`, `EmailProvider`,
`InvoicePartyRecord`, `HTTPRouteGroup` and `PostgresDatabase`. Constructors name
the type they construct, such as `NewDocumentService`. Implementation filenames
identify the same subject and role, such as `document_service.go` and
`invoice_data_source.go`. Keep established business names such as `Document` and
`Invoice`, and standard methods such as `Read`, `Close` and `Error`.

Boundary conversions use explicit helper names containing `Mapper`, and dedicated
`.mapper.go` files. Keep mapper functions in their existing boundary and preserve
validation and error handling. A mapper does not need an empty wrapper struct.

## Dependency direction

Models contain core values and validation. Interfaces describe the core needs
of their consuming domain using those values. Services coordinate use cases
through their own interfaces. Neither models nor interfaces import service
implementations. Core never imports SQL, HTTP, generated contracts, concrete
adapters or a container.

Repositories implement core repository ports and map persistence records to
core models. Each repository owns its explicitly named source interface, such as
`DocumentSource`, in its
`repos` package. These interfaces use data records and therefore stay outside
core. Data sources implement them, execute I/O and own complete transactions.
The identity security package implements core password and authorization needs.
No data or presentation package imports a core service implementation; root
bootstrap injects services through consumer-owned interfaces.

Presentation models cannot import handlers or routes. Handlers call their
injected service port and map generated responses; routes own bounded request
predecoding and group middleware. Shared HTTP transport can use identity value
models for its injected authentication/permission guard. This does not give
feature handlers access to identity persistence or service construction.

Workflow packages are a separate deterministic adapter role inside their domain.
They own workflow definitions, wire values and stable registration constants.
They may use core value models, deterministic standard-library helpers and the
SDK's `workflow` and `temporal` packages. They cannot import services, core ports,
data adapters, HTTP, clients, activities or sibling workflow packages. Core
models, interfaces and services cannot import workflows.

Each `data/<domain>/temporal` adapter owns its activities, dispatchers and local
service ports. It may import its own workflow package and core values. Concrete
services, foreign workflow packages and foreign adapters remain inaccessible;
bootstrap injects the needed services. Presentation contains only HTTP code.

## Cross-domain collaboration

Business behavior crosses domains through injected service interfaces owned by
the consuming domain. Such interfaces may use foreign value models and errors.
Root bootstrap connects providers and consumers; one domain does not import a
foreign service implementation, container or presentation module.

Repository/data-source collaboration is also allowed for deliberate database
joins. Prefer a single source-owned query or transaction over the shared schema.
Where one adapter needs another domain's data, inject a small consumer-owned data
port. Only repositories and data sources may use foreign data value records for
that purpose. They cannot import another domain's concrete repository or source.
Data models and security adapters are not collaboration points.

Legacy document adoption is an existing example: the document data source locks
an existing account row, then assigns unowned document rows in the same
transaction. It does not call the identity service while holding database locks.
Transaction ownership, lock order, authorization and account filters remain
explicit. A shared connection does not grant an unscoped repository operation.

## Shared resources and deliberate exceptions

Concrete containers stay in `bootstrap/<domain>/<domain>_container.go`, separate from the
pure core. They build the domain's sources, repositories, services and adapters.
Root bootstrap owns the pool, Temporal connection, worker and shutdown. Each
container borrows shared resources and closes only its own activities. Putting
concrete wiring inside core would reverse its dependency direction.

The shared PostgreSQL source exposes a concrete `PostgresDatabase` capability with only
`QueryRow`, `Begin` and `BeginTx`. It has a private pool and no close, migration,
configuration or raw-pool method. Domain sources receive that capability and
cannot close the pool through their constructor contract. Tests open their own
fixture connections when they need additional SQL operations.

Generated Jet rows and table builders remain one shared relational schema under
`data/postgres/generated`, beside the shared migration lifecycle. Handwritten
identity/document operations live in their respective data sources. Useful
aggregates live under each domain's data models; generated rows are not copied
or aliased merely to populate a directory. The canonical OpenAPI contract and
its generated router remain shared too.

These choices keep domain ownership and Go's acyclic package imports explicit.
The [code pattern map](../code-patterns.md) connects these conventions to their
implementation and enforcement. See [Temporal](temporal.md) for workflow
compatibility and worker ownership.

## Enforcement

Architecture tests classify layer, domain owner and package role, including
nested packages. They reject core infrastructure imports, foreign concrete
services/adapters/containers, cross-domain presentation, and shared helpers that
reach into feature implementations. Package-level restrictions cover normal,
aliased, blank and dot imports. Positive fixtures cover service value ports and
data joins, alongside negative fixtures for bypasses.

The checks also reject Temporal presentation packages, I/O in workflow packages,
and core dependencies on workflows. Workflow definitions require `.workflow.go`
filenames. Naming checks reject generic handwritten type and implementation file
names while leaving generated code and standard interface methods alone.

These source checks cannot prove that a join is appropriate or that a transaction
is correct. Review and the real PostgreSQL, API, Temporal and browser tests verify
those behaviors. Integration discovery includes every package under
`internal/data/...`, so moving an adapter cannot remove its suite from the Task
command.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
