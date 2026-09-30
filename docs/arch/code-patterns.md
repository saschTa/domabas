# Code patterns and where to find them

This map connects the main implementation patterns to their maintained guides.
It covers the backend, frontend and repository tooling. It is a navigation aid
for review, not a claim that static tests can prove every behavior correct.

Start with [the architecture overview](../../architecture.md). Follow
[AGENTS.md](../../AGENTS.md) for contributor commands and change requirements.

## Backend patterns

| Pattern | Rule and implementation | Detailed guide |
| --- | --- | --- |
| Domain ownership | Models, consumer-owned interfaces and services live under `backend/internal/domain/<domain>`. Data, presentation and bootstrap have separate roles. | [Domain structure](backend/domain-structure.md) |
| Explicit names and mapping | Handwritten types name their subject and role. Value files use `*.model.go`; dedicated boundary mappers use `*.mapper.go`. Generated names belong to the generator. | [Naming and dependency direction](backend/domain-structure.md) |
| Constructor injection | Root bootstrap creates shared resources. Domain containers borrow them and expose services to injected consumer ports. No service locator or generic repository framework. | [Dependency injection](backend/dependency-injection.md) |
| Business policy and transactions | Services choose claims, disclosure and transitions. Data sources own scoped queries and atomically check command preconditions. Cross-domain joins have one explicit transaction owner. | [Service policy and persistence](backend/service-policy-and-persistence.md) |
| HTTP contract | `contracts/backend/openapi.yaml` generates the Go boundary and Dart client. Domain routes decorate the single generated registry; strict validation and safe errors stay at the boundary. | [HTTP presentation](backend/http-presentation.md) |
| Relational data | Typed columns and child tables store operational entities. Documented immutable protocol snapshots are the narrow JSON exception. Jet builders and pgx remain in adapters. | [Persistence](backend/persistence.md), [PostgreSQL setup](backend/postgresql.md) |
| Migration safety | Embedded numbered migrations use an advisory lock and exact checksum history; applied files stay immutable. Tests use disposable schemas. | [Boundaries](backend/boundaries.md) |
| Authorization | Local sessions, namespace roles, explicit claims, ownership and system administration have separate meaning. Every use case checks current authority. | [Identity](backend/identity.md) |
| Durable jobs | Acceptance and queue intent commit together. Stable workflow IDs, execution ownership, idempotent writes and reconciliation handle retries and uncertain delivery. | [Background jobs](backend/background-jobs.md), [Temporal](backend/temporal.md) |
| Shared admission | Jobs reserve all worker and model-provider requirements atomically. Limits apply across instances; closure evidence governs release. | [Resource scheduler](backend/resource-scheduler.md) |
| File and search generations | Upload staging, retained originals, OCR revisions, embedding provenance and publication checks prevent obsolete processing from replacing current content. | [Document ingestion](backend/document-ingestion.md) |
| Pagination and refresh | Growing lists have bounded pages. Document cursors bind ordering and search criteria; totals and continuation follow each endpoint's contract. | [Document pagination](backend/document-ingestion.md#cursor-pagination), [HTTP contract](../../contracts/backend/openapi.yaml) |
| Credentials and model boundaries | Encrypted credentials stay outside logs and workflow payloads. Accepted jobs retain their model settings. Model output is validated before publication. | [Property AI](backend/property-extraction.md), [Chat](backend/ai-chat.md), [Email](backend/email-ingestion.md), [Paperless](backend/paperless-import.md) |
| Structured invoices | Exact decimals, source evidence, correction references and invoice children have explicit models and tables. | [Invoices](backend/invoices.md) |
| Small derived artifacts | Thumbnail discovery and rendering have durable jobs and independently bounded CPU work. | [Thumbnails](backend/document-thumbnails.md) |
| Live updates | Transactional PostgreSQL notifications trigger bounded, authorized WebSocket invalidations; clients fetch the data through the API. | [Realtime](backend/realtime.md) |
| Resource lifetime | Startup deadlines, runtime cancellation, readiness, worker failures and activity draining have explicit owners. | [Lifecycle](backend/boundaries.md#temporal) |

Backend structural enforcement lives in
[backend/tests/architecture](../../backend/tests/architecture). It checks imports,
package roles, names, workflow layout and selected service-policy violations,
including negative fixtures for common bypasses. It cannot prove transaction
correctness or complete authorization. Domain tests, real database tests,
[Temporal tests](../../backend/tests/temporal) and
[API E2E tests](../../backend/tests/e2e) check those behaviors.

## Frontend patterns

| Pattern | Rule and implementation | Detailed guide |
| --- | --- | --- |
| Layer boundaries | Immutable domain values and ports stay independent of Flutter and generated transport. Data sources own I/O, repositories map values, and presentation owns interaction. | [Frontend overview](frontend/index.md) |
| State ownership | Cubits emit immutable snapshots. Widgets own temporary form, focus and controller state. Asynchronous completion respects the owner's lifetime. | [Cubits and state](frontend/index.md#cubits-and-immutable-state) |
| Dependency and session scopes | `frontend/lib/app` builds public and authenticated dependencies. Sign-out, library switching and server changes dispose the correct scope and reject stale responses. | [Identity lifetime](frontend/identity.md), [Server configuration](frontend/server-configuration.md) |
| Transport and storage | Adapters bound binary responses, translate failures, support cancellation and avoid automatic retry of uncertain writes. Native credentials use secure storage; browsers use HttpOnly cookies. | [Platforms and transport](frontend/platforms.md) |
| Reusable presentation | `lib/ui` accepts display values, children and callbacks without feature models or Cubits. Responsive navigation and common job views use these presenters. | [Shared components](frontend/components.md), [Mobile navigation](frontend/mobile-navigation.md) |
| Background refresh | A framework-independent coordinator under `lib/scheduling` owns reads, dirty state and scheduling. Screens retain drafts, loaded history and cursors across refresh. | [Live updates](frontend/realtime.md) |
| Continuation and progress | Collections, job histories and conversations expose bounded continuation. Work continues on the server when a screen closes. | [Documents](frontend/documents.md), [Email](frontend/email.md), [Invoices](frontend/invoices.md), [Chat](frontend/ai-chat.md) |
| Concurrent settings edits | Revision checks prevent overwriting another saved configuration. Conflicts and uncertain writes require refresh while preserving the user's draft. | [Workload settings](frontend/workload-settings.md) |
| Local device state | Appearance and server preferences have their own lifetimes; scanner drafts remain local until explicit PDF submission. | [Appearance](frontend/appearance.md), [Scanner](frontend/scanner.md) |
| Platform assets | One canonical vector generates checked-in branding for all six platforms. | [Branding](frontend/branding.md) |

[frontend/test/structural/architecture_test.dart](../../frontend/test/structural/architecture_test.dart)
checks layer imports, names, mapper conventions, pure shared scheduling, shared
UI boundaries and Cubit ownership. Unit, repository and widget tests check state,
pagination, transport and scope races. Browser suites exercise selected complete
flows against real services. The [testing guide](../development/testing.md)
explains the required environments; a supported platform is not a claim that
its native build was run in every change.

## Tooling and generated artifacts

[Development tooling](tooling.md) explains Bun TypeScript automation, explicit
environment loading, process-tree ownership, cancellation, isolated test
infrastructure, checksum-verified downloads and releases. Go Task is the command
entry point. Runtime application code remains Go and Flutter.

Generated API, database and icon files are committed so an ordinary checkout can
build. Change their source and run the relevant generation task rather than
editing output by hand. Dependency changes update the relevant pins and lockfiles
deliberately. The testing guide distinguishes `task check`, database/Temporal
integration, API E2E, browser E2E and the CI baseline.

When a new pattern is introduced, update its owning guide and this map when it
adds a new shared convention. Every architecture guide must be linked from
[the main index](index.md) and its directory index. Plans record change-specific
research and validation; maintained guides describe the current implementation.
