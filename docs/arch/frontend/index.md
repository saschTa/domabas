# Flutter architecture

See [AI chat](ai-chat.md) for the private conversation workspace and independent
administrator model settings.

Domabas targets Android, iOS, web, Linux, macOS and Windows with Flutter 3.47.4 and
Dart 3.13.3. Its document workspace shows uploaded PDF, PNG and JPEG originals,
metadata, tags, extracted text, processing jobs and reindex progress. Identity
screens manage sign-in, personal and shared libraries, invitations, scoped grants
and system administration.

Start with [document workspace and design](documents.md), [shared UI components](components.md),
[platforms and transport](platforms.md), and [authentication lifetime](identity.md).
See [mobile workspace navigation](mobile-navigation.md) for the primary bar,
native Scanner action and More sidebar containing secondary destinations.
See [invoice workspace](invoices.md) for invoice provenance, exact amounts,
document links and paginated invoice details.
See [appearance and client preferences](appearance.md) for persistent System,
Light and Dark themes and their app lifetime.
See [third-party licenses](licenses.md) for the offline attribution reader and
repository-wide inventory.
See [application branding](branding.md) for the canonical Filed Paper vector and
the generated icons for all platforms.
See [native server configuration](server-configuration.md) for setup, persisted
addresses, connection checks and complete endpoint replacement.
See [email accounts and personal activity](email.md) for mailbox settings, safe
email viewing and the activity panel.
All pipelines and jobs follow the [unified pipeline UI rules](components.md#unified-pipelines-and-jobs):
one filterable jobs list, shared pipeline boxes and a common detail-page structure
with recorded step progress and failures.
See [mobile document scanning](scanner.md) for camera capture, durable local
drafts and explicit PDF submission on Android and iOS.
See [mobile sharing](mobile-sharing.md) for receiving images and PDFs from other
apps, iOS Keychain sharing and Android upload confirmation.

## Layers and composition

```text
lib/
  app/                         concrete clients, repositories and lifetimes
  domain/<domain>/
    models/                    immutable values, errors and validation
    interfaces/                repository and capability ports
  data/<domain>/
    models/                    adapter values and keys
    repos/                     repository implementations and source ports
    datasources/               generated API calls and platform I/O
  presentation/<domain>/
    cubits/                    application state and operations
    models/                    immutable presentation state
    views/                     feature screens
    widgets/                   forms, rendering and interaction controls
  ui/                          domain-independent dumb presenters
```

The domains are `document`, `identity`, `email`, `realtime`, `appearance`,
`scanner`, `server`, `paperless`, `invoice`, `chat`, `workload` and `licenses`.
The Paperless Settings screen accepts each
user's source URL and API token, starts durable imports and monitors persisted
progress through its repository and Cubit; it
does not execute the pipeline. See [Paperless import](../backend/paperless-import.md).
Admin settings → Paperless retrievals requires `system:paperless:manage` and is
available independently of namespace import permission. Its dedicated repository
and Cubit load and save installation-wide parallel retrievals (1–10) with an
expected revision. Refresh preserves an edited choice while showing the current
saved value; a conflict or uncertain write requires refresh before another save.
The screen explains source retrieval protection and the shared worker capacity used by imports.
Add domain services only when a use case
needs coordination; do not create empty layers or forwarding services. Domain code
has no Flutter, Bloc, HTTP, generated DTO or platform-storage dependency. Data
sources own I/O, repositories translate data and failures, and presentation uses
the domain ports. Concrete implementations are wired in `lib/app`, with constructor
injection and no service locator.

Handwritten classes and filenames identify their business subject and role,
including data sources, repositories, state and private helper types. Keep
already clear names such as `Document` and `Invoice`. Boundary conversion helpers
include `Mapper` in their names; dedicated mapper files use `_mapper.dart`.
Mapping stays in data adapters, with existing validation and failure translation.

Generated API models remain in data adapters. Renderer package types stay in
presentation, while binary transport stays in data. Shared UI takes display values,
children and callbacks and does not import domain models, Cubits, repositories or
app composition. Cross-domain code can consume domain value models; it cannot
import another domain's concrete adapters or presentation.

## Cubits and immutable state

The app pins `bloc` 9.2.1 and `flutter_bloc` 9.1.1. Session, libraries, account
management, system users, document processing and document state use actual Cubits
with immutable state snapshots. Widgets rebuild through `BlocBuilder`; the app subscribes to session
state to replace authenticated dependencies and the keyed navigator. Workspace
navigation has its own app-owned Cubit. There is no ChangeNotifier compatibility
layer or mutable view-model object emitted as state.

Cubits hold request coordination, validation and user-visible errors. Identity
Cubits preserve serialized session/storage operations and publish complete
snapshots after changes. Collections copy their input into unmodifiable lists.
Temporary form, focus, scroll, animation and PDF-controller state belongs to the
owning widget and is disposed there. Cubits stop accepting/publishing work before
closing their streams; asynchronous completions check their lifetime.

`AppDependencies` owns public transport. Each authenticated scope owns its
repositories and an immutable-token `SessionClient`. A namespace change replaces
the complete scope, including document resources. Logout cancels document requests
immediately but retains identity transport until revocation finishes. Exact-session
callbacks prevent an old unauthorized response from expiring a newer session.
The [identity guide](identity.md) describes persistence and logout ordering.

## Transport and contract

`contracts/backend/openapi.yaml` is canonical. `task generate` updates Go HTTP
code and the local Dart package in `frontend/packages/domabas_api`. Generated
outputs and dependency locks are committed, and normal builds need no generation.
Never hand-edit generated files.

The binary adapter uses `downloadDocumentWithHttpInfo()` and `bodyBytes`; the
pinned generator's convenience `downloadDocument()` incorrectly applies JSON
deserialization. `LimitedResponseClient` enforces a 100 MiB response ceiling while
streaming, before the generated client buffers the body. It checks declared and
actual byte counts, preserves response metadata and passes abortable requests
through. Data sources supply deadlines and cancellation for their consumer scope.
Expected transport/decode failures become domain failures; private server bodies
are not displayed to users. Writes are not automatically retried after an
uncertain response.

The native bootstrap restores the selected server before constructing API
dependencies, with explicit `API_BASE_URL` as an initial development default.
Web resolves `API_BASE_URL` first and otherwise uses its browser origin. The
Compose web server proxies API traffic to Go. No infrastructure hostname or
Temporal SDK belongs in the frontend domain or presentation.

## Extending and verifying

Add pure domain values/ports, change and regenerate the contract if needed, then
implement data adapters and constructor-injected Cubits/views. Keep permission
IDs as strings and derive visible capabilities from the authoritative session;
the server remains the authorization boundary.

`test/structural/architecture_test.dart` inspects all three layers, including
conditional imports, and rejects cross-layer and concrete cross-domain bypasses.
Unit tests cover immutable state, pagination, errors, cancellation and session
races. Repository tests exercise the real generated client through local HTTP.
Widget tests cover responsive forms and navigation. The browser integration suite
uses real Go/PostgreSQL/Temporal with disposable schemas and queues. Inspect the
running UI as well. See [test and CI prerequisites](../../development/testing.md)
and the [code pattern map](../code-patterns.md).

Authenticated scopes own live connections and retained dirty refresh state. See [live updates, fallbacks and draft preservation](realtime.md).

- [Administrator workload settings](workload-settings.md)
