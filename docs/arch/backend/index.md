# Backend architecture

The backend is one Go application with clear internal boundaries. It serves the
HTTP API and runs the Temporal workers that perform background work. PostgreSQL
stores application records; persistent file storage holds originals. A separate
private Go processor performs bounded document parsing, OCR and rendering.

For a plain-English explanation of the complete system, start with
[How Domabas works](../../../architecture.md). For commands, use the
[backend README](../../../backend/README.md).

## Responsibilities

| Layer | Responsibility |
| --- | --- |
| `domain/<domain>/models` | Business values, validation, errors and pure policies |
| `domain/<domain>/interfaces` | Small interfaces owned by their consumers |
| `domain/<domain>/services` | Authorized use cases and business transitions |
| `domain/<domain>/workflows` | Deterministic Temporal orchestration |
| `data/<domain>` | I/O, transactions, record mapping, activities and dispatchers |
| `presentation/<domain>` | HTTP request validation, handlers, response mapping and route groups |
| `bootstrap` | Concrete construction, shared resources and process lifetime |

Dependencies arrive through constructors. Services select policy; data sources
apply scoped, atomic commands. Domain code stays independent of HTTP, SQL and
generated boundary models. Workflow packages are the narrow exception for
Temporal's deterministic SDK APIs. Go architecture tests enforce package roles,
import direction, explicit names and selected policy boundaries.

The public API starts in [OpenAPI](../../../contracts/backend/openapi.yaml).
`task generate` produces both server types and the Dart client. Generated code
is committed and must not be edited by hand. Application migrations follow the
same principle: add a new migration, then regenerate database models when the
schema changes.

## Structure and shared mechanisms

- [Domain structure](domain-structure.md): folders, names, mappers and cross-domain ports.
- [Dependency injection](dependency-injection.md): domain containers and borrowed resources.
- [Service policy and persistence](service-policy-and-persistence.md): authority, disclosure and atomic commands.
- [HTTP presentation](http-presentation.md): routing, strict validation and safe responses.
- [Boundaries and lifecycle](boundaries.md): migration integrity, startup and activity draining.
- [PostgreSQL and storage](postgresql.md): databases, roles, schemas, extensions and files.
- [Relational persistence](persistence.md): typed data and documented snapshot exceptions.
- [Temporal](temporal.md): workflows, activities, queues, retries and retention.
- [Background jobs](background-jobs.md): durable acceptance, progress and cancellation.
- [Resource scheduler](resource-scheduler.md): shared worker and provider admission.
- [Realtime updates](realtime.md): committed notifications and authorized WebSockets.

## Feature guides

- [Identity and access](identity.md): accounts, libraries, roles, claims and invitations.
- [Document ingestion and search](document-ingestion.md): uploads, OCR, embeddings, edits and reindexing.
- [Document thumbnails](document-thumbnails.md): bounded previews and durable rendering jobs.
- [Document property AI](property-extraction.md): optional extraction and provider configuration.
- [Invoices](invoices.md): structured XML, optional AI and exact relational records.
- [Private AI chat](ai-chat.md): conversations, provider steps and document tools.
- [Email ingestion](email-ingestion.md): IMAP accounts, encrypted credentials and activity.
- [Paperless-ngx import](paperless-import.md): durable source discovery and retrieval.

## Validation

Unit tests cover policies and use cases. Architecture tests inspect production
source and test their own rejection rules. Real PostgreSQL tests check queries,
transactions and migrations; Temporal tests check workflows and worker recovery;
API and browser E2E tests check selected complete flows. Test workers use unique
queues and disposable schemas.

See the [code pattern map](../code-patterns.md) for links to implementation and
enforcement, and the [testing guide](../../development/testing.md) for commands,
prerequisites and the distinction between CI and local validation.
