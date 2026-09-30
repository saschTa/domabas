# Relational operational data

## Decision

Store normal application data in typed relational columns and related tables.
Do not use JSON or JSONB documents as the operational model for entity reads,
writes, filters, search, relationships or analysis. Do not hide the same pattern
behind JSON aggregates in SQL or serialized domain objects in repositories.

Typed columns make constraints, relationships, exact numeric values and future
analysis explicit. Ordered child tables represent collections; composite foreign
keys preserve namespace ownership and cascading deletion. Data adapters map rows
to domain values, and repositories preserve the domain/storage boundary.

JSON at public HTTP, provider and cursor boundaries is a transport format and is
unaffected. Existing immutable processing-configuration snapshots are retained
for job reproducibility and compatibility. Such protocol/snapshot storage is an
explicit exception, not a template for operational entities. A new exception
must be explained in architecture documentation; ordinary properties use columns.

## Invoice implementation

`invoices` stores identity, provenance, dates, ISO currencies, totals, seller and
buyer fields, and payment details. `invoice_lines`, `invoice_taxes`,
`invoice_allowances`, `invoice_references` and `invoice_notes` store ordered
collections. Amounts, prices, quantities and rates use PostgreSQL `numeric`;
missing values use NULL and are mapped to absent domain values. There is no
invoice JSON/JSONB column or operational serialized invoice payload.

The search vector is a derived lexical index of invoice fields. The repository's
write transaction replaces the header and child rows, updates this index and
advances the ingestion checkpoint together. Original source XML is preserved as
evidence and is not queried as the invoice model. Reads page headers first and
batch-load the selected invoices' children in the same authorized transaction.

## Migration policy

Migration history remains immutable and checksum-verified. Add a new migration
for schema changes and regenerate the database models when tables change. Keep
retained application data and volumes intact; test harnesses clean up only their
own disposable schemas and resources. Fresh checkouts build from the committed
migrations and generated models.

Document AI processing uses typed `document_ai_jobs` rows for each attempt, status,
stage, current document/OCR generation, admission, delivery lease and retained
execution ownership. The row is also the transactional outbox intent. Its
configuration JSON is an immutable protocol snapshot under the existing exception;
operational queries use typed columns. `document_pipeline_jobs` is a relational
union view over ingestion history and AI attempts for paginated job/activity reads.

## Chat tool protocol snapshots

Chat settings, messages, turn states, configuration references, admission leases,
tool names/arguments and source relationships use typed columns. The immutable
`chat_tool_results.result_text` is the exact serialized reply sent to a model for
one completed tool invocation. Retaining this bounded protocol snapshot lets an
activity resume without silently changing earlier evidence. It is an explicit
protocol exception: normal SQL reads never query or aggregate its JSON, and
operational search, document relationships, progress and source lists use
relational data. Migration 028 performs a one-time backfill of typed outcome and
continuation columns from these immutable snapshots for retained turns. It keeps
the original replies unchanged. Runtime loop decisions read `outcome_code`,
`next_offset`, typed call arguments and the `chat_sources` child rows.
Fresh authorization checks source records before reusing a reply. Chat provider
settings are copied as typed turn fields, not serialized configuration payloads.

Model context requests use typed `context_length` columns in chat settings and
accepted turns, and `llm_context_length` in active document processing settings.
Document jobs copy the requested value into their existing immutable
configuration snapshot. Historical snapshots are preserved; missing context
continues to identify the original 16,384-token request. Current configuration
adoption creates a new revision instead of rewriting accepted history.

Scheduler settings, waiters, grants and requirements use typed columns and child tables. Document provider requirements are projected from immutable job/configuration snapshots when they are written and during the one-time retained-ownership migration; scheduler reads do not query JSON. See [resource scheduling](resource-scheduler.md).
