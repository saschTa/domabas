# Architecture guides

Start with [How Domabas works](../../architecture.md) for a plain-English tour of
the components and central mechanisms. The [code pattern map](code-patterns.md)
shows where implementation conventions are documented and checked. Use the
[development guide](../development/index.md) for commands and setup, or the
[testing guide](../development/testing.md) for test suites and prerequisites.

## Backend

| Guide | What it explains |
| --- | --- |
| [Backend overview](backend/index.md) | Responsibilities, dependencies and how to navigate the backend |
| [Domain structure](backend/domain-structure.md) | Folders, naming, mapper files and cross-domain boundaries |
| [Dependency injection](backend/dependency-injection.md) | Constructors, domain containers and resource ownership |
| [Service policy and persistence](backend/service-policy-and-persistence.md) | Authorization, business decisions and atomic commands |
| [HTTP presentation](backend/http-presentation.md) | Generated routing, request validation and response mapping |
| [Boundaries and lifecycle](backend/boundaries.md) | Migration integrity, startup and safe shutdown |
| [PostgreSQL and storage](backend/postgresql.md) | Databases, roles, schemas, extensions, migrations and persistent files |
| [Relational persistence](backend/persistence.md) | Typed records, child tables and permitted JSON snapshots |
| [Temporal](backend/temporal.md) | Workflows, activities, task queues, retries and worker lifetime |
| [Background jobs](backend/background-jobs.md) | Durable acceptance, progress, cancellation and recoverable pipelines |
| [Resource scheduler](backend/resource-scheduler.md) | Shared worker/provider limits and fair admission |
| [Identity and access](backend/identity.md) | Authentication, libraries, scoped claims, invitations and administration |
| [Document ingestion and search](backend/document-ingestion.md) | Uploads, OCR, embeddings, search, edits, jobs and reindexing |
| [Document thumbnails](backend/document-thumbnails.md) | Discovery, rendering, job history and preview delivery |
| [Document property AI](backend/property-extraction.md) | Optional metadata extraction and model configuration |
| [Invoices](backend/invoices.md) | Structured and AI extraction, exact amounts and invoice storage |
| [Private AI chat](backend/ai-chat.md) | Private conversations, model callbacks and authorized document tools |
| [Email ingestion](backend/email-ingestion.md) | IMAP providers, encrypted credentials and personal activity |
| [Paperless-ngx import](backend/paperless-import.md) | Source pacing, checkpoints and durable import outcomes |
| [Realtime updates](backend/realtime.md) | PostgreSQL notifications, WebSockets and access checks |

## Frontend

| Guide | What it explains |
| --- | --- |
| [Frontend overview](frontend/index.md) | Layers, Cubits, immutable state and dependency ownership |
| [Shared UI components](frontend/components.md) | Responsive surfaces, navigation, jobs and pipeline views |
| [Mobile navigation](frontend/mobile-navigation.md) | Bottom navigation and access to secondary destinations |
| [Document workspace](frontend/documents.md) | Browsing, searching, viewing, editing and processing screens |
| [Invoices workspace](frontend/invoices.md) | Filters, exact amounts, provenance and paginated details |
| [AI chat](frontend/ai-chat.md) | Conversations, progress, source links and administrator settings |
| [Workload settings](frontend/workload-settings.md) | Shared resource limits and concurrent-edit handling |
| [Email and activity](frontend/email.md) | Account settings, safe email rendering and job progress |
| [Mobile scanning](frontend/scanner.md) | Camera capture, page correction, local drafts and PDF submission |
| [Mobile sharing](frontend/mobile-sharing.md) | iOS Share Extension, Android received files and upload confirmation |
| [Platforms and transport](frontend/platforms.md) | Six platform hosts, HTTP clients, certificate trust and session storage |
| [Server configuration](frontend/server-configuration.md) | Native setup, saved addresses and replacing a server scope |
| [Identity lifetime](frontend/identity.md) | Sign-in, library switching, secure sessions and teardown |
| [Appearance](frontend/appearance.md) | System, light and dark themes and client preferences |
| [Third-party licenses](frontend/licenses.md) | Offline dependency notices, search and license inventory maintenance |
| [Branding](frontend/branding.md) | Canonical artwork and generated platform icons |
| [Live updates](frontend/realtime.md) | Refresh coordination, fallback polling and preserving user work |

## Shared conventions and tooling

- [Code pattern map](code-patterns.md): implementation, documentation and enforcement.
- [Development tooling](tooling.md): Bun automation, process ownership, generation, tests and releases.
