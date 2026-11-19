# Backend dependency injection

Root `bootstrap/backend_app.go` owns shared resources and process lifetime. Each domain
assembles concrete dependencies in `bootstrap/<domain>/<domain>_container.go`. Core
models, interfaces and services live together under `domain/<domain>`, while
concrete construction stays outside core. Dependencies are ordinary constructor
arguments; there is no service locator or dependency injection framework. See
[domain structure](domain-structure.md) for the complete layout and import rules.

## Document construction

The document container borrows the database and constructs document services, storage, the processor client and the inference adapter. Root bootstrap passes those services to the HTTP handlers and native pipelines. Workers call the same service ports as other clients of the domain.

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

Root opens and migrates PostgreSQL, constructs the domain containers and starts the realtime listener and native executor. Shutdown cancels discovery and joins running jobs before closing shared resources.

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
