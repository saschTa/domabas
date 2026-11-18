# Domabas product context

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Individuals and households managing their private documents are the primary
audience. When everyday workflow needs compete, prioritize this audience.

Users collect documents from files, paper, email and an existing archive. They
need to find the right original, understand its contents, organize it and share
selected libraries with trusted people. Library owners, invited members and
installation administrators have different responsibilities and permissions;
ordinary document work should not require understanding the hosting stack.

## Product Purpose

Domabas is a self-hosted document library: all your documents, searchable in one
central place. It brings originals, extracted text, metadata and processing
history into an accessible workspace.

Success means users can reliably capture documents, find and read them later,
understand what processing has actually completed, and control who can access
their libraries. Search and document access remain useful independently of
optional chat or AI extraction.

## Positioning

Domabas combines a personal document archive, full-text and semantic search,
controlled library sharing and local document processing. Storage, processing
and AI can run on the operator's own hardware; no cloud account is required.
Administrators can optionally configure external AI services. Do not turn this
choice into a claim that content can never leave the installation.

The product is intended for private installations and trusted users. It is not
positioned as a public upload service or an enterprise compliance system.

## Operating Context

The existing Flutter client supports web, Android, iOS, Linux, macOS and Windows.
Use one shared Domabas interface with platform-specific interactions, rather
than separate mobile product identities. Adapt navigation, input, window insets,
file handling, scanning and sharing to the host platform. Preserve all six
targets. The current redesign focuses on desktop screens.

Browser clients use the hosted application's origin. Native clients select and
remember a Domabas server. Users work within a selected personal or shared
library; account identity, library membership and system administration remain
distinct. Server and library changes must not leak content or drafts across
scopes.

Document ingestion, OCR, indexing, imports and optional AI can take time. The
interface must remain usable while work runs and must distinguish accepted,
waiting, running, failed and completed work from recorded evidence.

The production system uses a Go API, PostgreSQL, Temporal, a private document
processor and Ollama. The HTML design study is a prototype, not a replacement
for the Flutter client or an alternate application runtime.

## Capabilities and Constraints

- Upload PDF, PNG/JPEG and EML originals; extract text, use OCR where needed and
  generate document previews. Mobile scanning and supported operating-system
  share flows feed the document library.
- Search by words or meaning. Organize with tags and properties, and filter by
  document type, sender, recipient and other supported fields.
- Import from IMAP email and Paperless-ngx. Imported documents continue through
  the same document-processing responsibilities as other uploads.
- Read supported structured invoice formats and optionally extract invoice
  information with AI. Preserve source evidence and exact currency values;
  invoice extraction does not establish a payment or approval workflow.
- Offer private, library-scoped AI conversations with links to the documents
  used in answers. AI output remains reviewable and is not guaranteed correct.
- Support personal and shared libraries, invitations, roles and explicit
  permissions. The backend is the authorization authority. Library ownership
  does not imply system administration.
- Preserve functionality during the redesign: pagination, filters, drafts,
  original document rendering, recovery states, background refresh and scoped
  access. Evolve the existing shared UI library rather than creating a second
  application framework.
- Use real APIs and persisted data in production. Fictional documents and
  activity in the design study are examples only. A data-derived ambient
  background remains a proposal; complete daily activity aggregates and precise
  first-index history are not currently supplied by a background statistics API.
- Keep originals and reading content faithful to their source. Appearance
  choices must not recolor original pages or obscure meaningful document data.

Current behavior and implementation boundaries are documented in the
[architecture overview](architecture.md), [frontend architecture](docs/arch/frontend/index.md),
[UI component guide](docs/arch/frontend/components.md) and
[public API contract](contracts/backend/openapi.yaml). Data-flow and retention
claims must agree with the [privacy guide](docs/development/privacy.md).

## Brand Commitments

The product name is **Domabas**. Preserve the canonical
[Filed Paper mark](frontend/assets/branding/domabas-mark.svg) as the source for
branding assets.

The user selected **Glacier**, a frosted-glass direction with both light and dark
appearance, for the redesign. This is a binding direction, not a claim that the
production interface has already migrated. Detailed visual rules and component
specifications belong in design guidance, not in this product record.

## Evidence on Hand

- The [README](readme.md) documents the product's existing features and hosting
  model; the [frontend guide](frontend/README.md) covers client capabilities and
  platform setup.
- [Repository screenshots](docs/screenshots/index.md) show the existing web
  application with fictional documents and users. They are interface evidence,
  not customer testimonials or proof of adoption.
- The production code, architecture guides and API contract provide the
  functionality baseline. The separate design exploration does not certify
  complete feature parity, native performance or accessibility conformance.
- No customer endorsements, adoption numbers or comparative performance claims
  have been established in this product context. Do not invent them.

## Product Principles

1. **Personal document work comes first.** Make capture, retrieval and reading
   understandable without requiring users to think like system administrators.
2. **Control is explicit.** Preserve clear library boundaries, ownership,
   permissions and choices about where processing occurs.
3. **Show evidence honestly.** Distinguish saved originals, extracted data,
   generated answers and recorded processing outcomes. Unknown is not zero or
   complete.
4. **Consistency preserves continuity.** Common interactions should behave
   predictably across screens and clients without losing drafts, filters or
   position.
5. **Enhancements support the task.** Optional AI, appearance and background
   features must leave core document workflows usable and legible.

## Accessibility & Inclusion

Preserve the existing UI guide's keyboard access, focus and selection semantics,
accessible labels, tooltips, enlarged-text handling, minimum interactive targets
and reduced-motion behavior. Controls must not depend on hover alone. Respect
platform navigation and input expectations, including touch and keyboard use.

Light and dark appearance are required by the selected direction. Decorative
transparency must have an opaque alternative, and document reading surfaces must
stay legible. No formal accessibility certification or additional
audience-specific requirement has been established; do not claim conformance
without verification.

## Open Decisions

- Detailed mobile adaptations of Glacier remain to be designed; the confirmed
  policy is a shared Domabas interface with native interactions.
- Ambient activity metrics, aggregation coverage and their production API remain
  future implementation decisions.
- Formal accessibility targets and any commercial positioning beyond the
  documented self-hosted product have not been specified.
