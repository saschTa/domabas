# Document ingestion and search

The backend accepts PNG, JPEG, PDF and EML originals through `POST /api/v1/documents/upload`.
The multipart request has exactly one `file` and one `metadata` JSON string part,
in either order. Uploads are limited to 100 MiB, metadata to 32 KiB and the complete
request to 100 MiB plus 64 KiB. The upload and download routes have a 120 second
deadline; search allows 30 seconds and ordinary routes retain 10 seconds. Four
concurrent upload slots bound filesystem work. Nginx and the Go server support
these limits.

Metadata includes title, description, tags, document kind, sender, recipients,
CC, BCC, date, subject and message ID. Uploaded files also record SHA-256, MIME
type, original filename, ingestion time and uploader. Dates use `YYYY-MM-DD`.
PATCH omits unchanged fields and clears optional strings or arrays with empty
values. Explicit nulls, duplicate JSON keys and unknown fields are rejected.
Existing metadata-only create/list/read behavior remains available.

Namespace claims separately authorize upload, update, download, search, retry,
OCR reading/correction, deletion, job history and reindexing.
The owner receives all registered namespace claims. The system claim
`system:document-processing:manage` authorizes installation configuration and does
not grant access to another namespace's files. SQL transactions recheck current
session, credential revision, membership and permissions before publishing changes.
A single joined MVCC query reads that authority without locking account, user,
membership or session rows. All required claims are evaluated against that value.
An operation authorized before concurrent revocation may finish; every subsequent
transaction checks again, including upload acceptance after the file is streamed.
Read operations use read-only repeatable-read snapshots, including job counts and
title visibility, search, OCR, configuration and upload preparation. They acquire
no explicit row or advisory locks and never initialize configuration.
A unique namespace/hash constraint rejects duplicate bytes, including concurrent
uploads, without consulting another namespace's duplicates.

## Storage and acceptance

The filesystem adapter uses two separately configured roots. Relative paths are
chosen by the server as `namespace UUID/uploader UUID/document UUID/original`.
An `os.Root` capability contains file access; supplied filenames never select a
path. Owned roots cannot be group/world writable; nested directories and files
are private. Both roots must be writable for readiness.

Before reading the file, SQL creates a five minute upload reservation. The staged
original is written and synced before a transaction publishes its metadata,
processing generation and outbox row. The reservation fences acceptance against
abandonment or expiry cleanup. A connection failure during commit preserves the
file until conditional abandonment proves that no accepted row owns it.

Finalization copies between the two roots, verifies bytes/hash, syncs, renames and
syncs directories before SQL marks the generation ready. Staging removal follows
publication. The reaper also handles a crash between those two operations through
a durable retiring reservation. Failed documents retain their originals for
inspection, download and retry. Authorized explicit deletion uses durable cleanup;
no automatic retention policy is included.

## Durable processing

Deterministic definitions live in `domain/document/workflows`, including
`document_ingestion.workflow.go` and `document_metadata.workflow.go`.
`data/document/temporal` owns `DocumentIngestionActivities`,
`DocumentMetadataActivities` and `DocumentIngestionDispatcher`. Bootstrap injects
their service ports and registers the existing versioned workflow/activity names.

An outbox dispatcher leases pending delivery rows and starts the deterministic
workflow ID for a document generation. It rejects duplicate workflow IDs and
verifies the existing workflow type, queue and ID-only input before acknowledging
an already started execution. The acknowledged run ID is persisted. Crashes after
Temporal accepts work but before SQL acknowledgement are safe to replay.
Namespace history retention must remain at least 24 hours, including for external
Temporal deployments. Startup and every readiness probe verify this floor so
closed history cannot expire inside the delivery window. Compose uses 72 hours.

New documents use `domabas.DocumentIngestion.v2`: extraction, embedding and
finalization run through injected application ports. Finalization publishes ready,
searchable state and its downstream intent in one SQL transaction. Property or
invoice processing cannot reverse ingestion success. Intermediate text, invoice
source evidence and vectors stay in PostgreSQL; history carries identifiers and
sanitized failure codes. The persisted `split_pipeline` flag selects the workflow
name and deterministic ID prefix before admission. Retained v1 generations keep
their original invoice/property stage sequence and exact input bytes; the old
metadata diagnostic v1/v2 names also remain registered.

`document_ai_jobs` stores a typed row for each downstream attempt, including its
status, stage, generation, OCR revision, immutable configuration snapshot,
outbox lease, workflow identity and execution ownership. New finalization records
an explicit skipped attempt when both AI switches are off and no structured
invoice source exists. Older combined jobs have no fabricated AI outcome. Empty
OCR corrections that publish directly also enqueue through the same transactional
trigger. The follow-up snapshots the current configuration at publication, so an
AI settings edit during ingestion applies when that document becomes searchable.

`domabas.DocumentAI.v1` uses a separate task queue ending in `-ai`, worker,
dispatcher and shared resource reservations across replicas. It processes structured
invoice XML or enabled invoice AI, then enabled property extraction, and finally
records its own completion. A hung model retains its provider and worker permits, so new work starts only when the shared budget allows it. AI
failures preserve their failing step and never update ingestion state, original
publication or embeddings. Disabled or empty invoice inference does not erase
an existing invoice; a completed explicit negative classification can do so.

The [resource scheduler](resource-scheduler.md) admits the complete worker/provider requirements before workflow delivery. New ingestion never cancels running AI. Waiting jobs hold no activity slot and have no delivery deadline until admitted. Jobs sharing Ollama contend for the same pool; external providers have their own pools. Retained workflow names, inputs and command order remain unchanged.

Follow-up reads and writes lock the document first and verify the latest attempt,
ready ingestion generation and current OCR revision. Property publication also
checks metadata revision and fills only missing values. Correction, retry,
reindexing, deletion and newer AI attempts supersede/cancel obsolete attempts.
Dispatch verifies duplicate executions by workflow ID, type, task queue and exact
input. Cancellation retains admission until the owned execution closes; missing
unlimited history is not evidence of closure. The AI worker drains before shared
model clients and PostgreSQL close.

`POST /api/v1/documents/{id}/ai/retry` uses `documents:retry`, a client request UUID
and the expected configuration revision. Repeating that request returns the same
attempt. It leaves ingestion generation, effective text and vectors unchanged.
The processing response has an independent optional `ai` summary; job pages use
server-side `pipeline=ingestion|ai` filtering before cursor pagination and expose
the pipeline version. Personal activity includes separate AI entries.

The shared scheduler controls deployment-wide concurrency. Administrator workload settings replace independent ingestion and AI environment limits. Each document reserves its complete resource vector through verified execution closure. Waiting work holds no activity slots or delivery deadlines. Lower limits drain naturally and do not trigger reindexing. See [resource scheduling](resource-scheduler.md) for fairness, provider pools, foreground headroom and worker sizing.

New executions have no whole-workflow or SQL processing deadline. Model HTTP
calls retain caller cancellation without adding an elapsed-time limit. Temporal
requires an activity deadline: invoice, property, embedding and new extraction
activities use a ten-year fallback with three-second heartbeats and a 15-second
heartbeat timeout. The private processor spools each bounded original before
waiting for a CPU slot, within its bounded request envelope. Its 490-second
server body-read timeout still applies; it does not limit the later CPU wait.
After acquiring CPU capacity, OCR has a 480-second execution limit and 120
seconds per Tesseract call. The remote extraction request keeps caller
cancellation without spending the OCR budget on queue time. Version markers
preserve four-, eight- and sixteen-minute activity commands in retained histories.
Finalization retains its four-minute activity limit. Provider HTTP 429/503 and
processor overload use a 65-second retry delay. Embedding, invoice and property
steps permit up to four retries (five total attempts); terminal errors do not
retry. Other transient errors use shorter exponential retry delays. Retained
workflow branches keep their prior three-attempt policy. Extraction and
finalization keep their existing three-attempt policies. A model that never responds while its worker
remains healthy requires operator cancellation or restart.

The 24-hour delivery deadline starts at admission and governs work that has not
started. Processing records separately track processing_started_at and the
unlimited_inference mode. The execution row stores a zero execution timeout and
the workflow input adds the optional unlimitedInference field. Existing rows and
histories retain their 900-second workflow/SQL limits and original activity options.
Every stage still checks generation and state; late work cannot publish a newer
generation. A retry creates a new generation. Finalization remains idempotent.

Reconciliation cancels running unlimited workflows whose generation was deleted,
superseded or failed, then retains admission until confirmed workflow closure.
Missing history cannot prove closure of an unlimited execution merely by elapsed
time, so that reservation remains held for operator investigation. Keep Temporal
history long enough for the maximum expected backend outage; losing closed
history before reconciliation can strand a reservation. Startup and worker
shutdown continue to cancel and drain owned I/O.

Shutdown stops the dispatcher, drains activities and closes private document
resources before the shared Temporal client and database. Startup and readiness
include the processor, writable storage, database, Temporal namespace and worker.
Loading configuration or running migrations does not contact model services.

## OCR and embeddings

A private Go processor runs in a separate resource-limited Compose container.
Startup downloads missing, immutable Tesseract language files and the pinned
Ollama model, verifies cache hashes and warms inference before becoming ready.
Retained complete caches start without downloading again; corrupt or drifted
artifacts fail readiness. The processor keeps ten extraction slots and sizes embedding slots to half its
configured Ollama queue (minimum one). Requests wait cancellably for private
processor capacity within a bounded active/waiting envelope. Request bodies and
private inference calls remain bounded and cancellation-aware.
Ollama defaults to a 128-request scheduler queue and two loaded models. The pinned Ollama runtime forces embedding models to use one inference
slot, so concurrent embedding requests wait inside Ollama. Semantic queries share
embedding capacity with ingestion. Neither service is a public authenticated
application API.

PDFium runs the module's pinned WebAssembly binary in wazero with no mounted
filesystem, a 1 GiB linear-memory ceiling and a hard child-process deadline.
PDFs are bounded to 200 pages and 20,000 inspected page/form objects per page
(including nested forms), for at most 4 million inspections per document. Each
source image is bounded to 50 million pixels before decoding. PDF pages use
200 DPI when they fit that raster budget; larger pages use the highest integer
DPI from 1 through 200 that keeps the rounded bitmap within 50 million pixels.
Native text is preserved without requiring a raster allocation. Invalid page
geometry or an OCR page that cannot fit even at 1 DPI is rejected. Embedded
source images retain their decoding bound even when the page is downscaled.
Aggregate extracted text is bounded to 2 MiB. Form nesting remains bounded to
16 levels. Processor JSON responses are bounded to 16 MiB to allow escaped
text and base64 invoice XML. Native PDF text is preserved, and raster content is
rendered for OCR, including mixed pages.
PNG/JPEG decoding is bounded before allocation. Tesseract runs as a child process
with bounded output and a deadline. The processor container adds CPU, memory,
process and temporary-storage limits. Compose defaults to 4 GiB of processor
memory. The image uses private disk-backed `/app/tmp` for queued originals and
OCR scratch, avoiding the separate 2 GiB `/tmp` tmpfs for those files. Spooling
stays within the processor's bounded request envelope; a queue budget of 128
allows at most 128 accepted requests, each original limited to 100 MiB, plus
scratch for up to ten active OCR jobs. Provision disk and memory for the selected
concurrency. Normal completion and shutdown remove owned temporary directories;
after a hard crash, container recreation discards any remaining scratch. No
application document or database volume is used for scratch. Native processors
use their configured operating-system temporary directory. Resource bounds do
not guarantee completion for every document below the pixel ceiling.

Invoice attachment inspection has independent failure evidence: malformed,
multiple, oversized or excessively numerous invoice attachments produce a bounded
`invalid_invoice` diagnostic while page text extraction proceeds. The downstream
invoice step reports that diagnostic. Page geometry, actual PDF corruption and OCR
resource errors retain their mandatory processing failures.

The processor compiles PDFium once at startup into a private, parent-owned
temporary wazero cache. Child workers receive that cache path and reuse only
compiled engine code. Each extraction still creates and closes its own runtime,
guest memory and document handles. The cache has no document contents, is not
mounted into WASM, and is removed after child jobs drain. Tests inject an owned
extractor cache and verify cache reuse, cancellation and document isolation.

Manifest 2 adds `document-content-v2` extraction with bounded MIME parsing for
EML. Successful email extraction records `mime`, `domabas-mime`, version `1`, and
no OCR weights. PDF and image extraction records its actual Tesseract evidence.
Queued work and historical unknowns do not invent an extraction method. The
private processor still accepts retained manifest-1 PDF/image requests with their
original `tesseract-pdf-image-v1` identity and unchanged fingerprint encoding;
that historical revision never accepts EML. New installed configuration adoption
creates its normal revision and automatic reindex through the existing pipeline.
See [email ingestion](email-ingestion.md) for MIME and attachment failure bounds.

Defaults are Tesseract 5.5.3 with Leptonica 1.87.0, `tessdata_fast` English and
German language files, and Nomic Embed Text v1.5 on Ollama 0.34.1. The embedding
model produces 768-dimensional vectors. Compose uses CPU inference by default;
development can select supported acceleration through the
[runtime selector](../../development/compose.md#select-the-development-ollama-runtime).
Its semantic baseline is English;
German OCR and lexical search do not imply equivalent cross-language semantic
quality. Configuration supports English, German or both and automatic or single
block segmentation. Each ingestion generation snapshots its mandatory configuration and provenance.
OCR or embedding changes commit an automatic reindex batch for retained originals.
AI-only changes commit a durable rescheduling revision, sequence cutoff and cursor;
maintenance scans at most 100 accepted documents per transaction and queues
follow-up attempts for ready documents. Pending ingestion snapshots current AI
settings when it publishes. Existing reindex batches retain their own immutable
configuration and continue across AI-only revisions. AI changes preserve searchable
state, ingestion generations and vectors. Identical saves create no work.

Runtime and model pins live in the
[processor manifest](../../../backend/internal/data/document/datasources/processor/document_pins.go),
[processor image](../../../infra/document-processor/Dockerfile) and
[Go module](../../../backend/go.mod). Redistributed notices and source-attestation
limits are in [third_party](../../../third_party/README.md).

## Search and metadata edits

The app uses `hybrid` search: current metadata and text provide exact and fuzzy
word matches, and ready vectors add meaning-based matches. Relevance ranks
title/properties first, document text second and semantic-only matches third.
Within each lexical tier, exact matches precede fuzzy matches. The separate
`fulltext` and `semantic` API modes retain their existing behavior.

Hybrid treats the query as plain text with PostgreSQL's `simple` parser. Every
query lexeme must match the metadata or the metadata plus one current text chunk.
Exact words score 1; words of at least four characters containing a letter may
instead match a whole word with trigram similarity of at least 0.3. Short words
and numbers require exact matches. A semantic-only document must have cosine
similarity of at least 0.55. These thresholds are relevance heuristics, not
confidence probabilities. Punctuation-only queries have no results. Empty hybrid
queries use filter-only browsing and do not contact the processor.

Migration 013 installs the trusted PostgreSQL `pg_trgm` extension at version 1.6
in `public` under the existing database-wide migration lock. It validates an
existing extension's version/schema. Its schema-local immutable scoring function
uses explicitly qualified extension calls; retained metadata and chunks work
immediately without reindexing. Tests share the extension but own and remove only
their application schemas. No document data moves into `public`.

PostgreSQL stores exact machine text, an independent manual correction, bounded
overlapping chunks and vectors. Full-text search uses PostgreSQL's `simple`
configuration and includes current manual metadata and current-generation text.
Metadata and OCR corrections update lexical search immediately. Vectors describe
the current effective OCR revision rather than subsequent metadata edits.

Semantic search uses pgvector 0.8.6 cosine distance over the existing 768-dimensional
embeddings. Migration 029 adds an HNSW expression index on the stored arrays cast
to `public.vector(768)`; original double precision arrays stay unchanged. New
embeddings and updates maintain this index automatically. There is no library
chunk-count cutoff and no capacity rejection.

Relevance retrieval asks the index for a batch of 400 nearest eligible chunks, then
reranks candidate documents using the best of all their eligible chunks. Search
sets `hnsw.ef_search=200` and enables relaxed iterative scans; final document
ordering uses the calculated score and existing deterministic tie breakers.
PostgreSQL may choose exact scanning for small or selective corpora. A short
candidate page is retried with exact pgvector calculations so duplicate chunks or
a deep cursor cannot incorrectly end continuation. Explicit title/date sorts use
exact pgvector calculations directly. HNSW relevance is approximate: these
measures improve recall but do not promise every possible semantic match.
Expression statistics on the immutable model-space tuple keep PostgreSQL from
severely underestimating eligible processing rows. Normal auto-analyze maintains
these statistics; migration 029 also analyzes retained rows after building the index.
Search transactions use `plan_cache_mode=force_custom_plan`, so cached statements
keep accounting for the current namespace, model and filter values instead of
falling back to an unsuitable generic plan after repeated searches. The setting
is local to the transaction and does not force use of an index for selective data.

Kinds, tags, sender and recipient filters use one shared predicate before candidate
selection. Semantic chunks must have ready processing, the current generation and
OCR revision, and the captured embedding space: model name, digest, 768 dimensions,
embedding-input revision and indexing revision. The authorized SQL transaction
rechecks that this tuple is still current. A shared HNSW index can affect recall
between namespaces; predicates prevent foreign rows from becoming candidates,
and selective/deep pages retain exact fallback. Partitioning by namespace is a
future option if measured production recall or scale requires it.

Nonempty hybrid and semantic responses omit total and expose continuation through
`nextCursor`. Full-text and empty hybrid requests retain exact totals. No candidate
count is presented as an exact library count. Results contain bounded snippets;
vectors and complete OCR text never appear in collection or metadata responses.
The separately authorized OCR endpoint returns bounded exact text.

Hybrid keeps complete lexical discovery alongside approximate semantic discovery
and the same `documents:search` claim. Metadata-only documents and current lexical
text remain searchable while processing is pending or failed. Inference failures
remain explicit. Chunk scores are materialized once per search statement so
filtering and ordering reuse expensive multiword fuzzy calculations. The lexical
branch still scans eligible current chunks; HNSW accelerates semantic retrieval.
Search statements have a ten-second deadline, inside a 30-second HTTP request
budget for query embedding and up to two search passes. Transactions retain
repeatable-read isolation; removing a corpus-size cutoff does not remove resource
timeouts. Search failures log HTTP status and stable code without query text,
filters or cursors. Dispatcher warnings include task queue, error type, Temporal
status and SQLSTATE where available; document warnings identify dispatch versus
reconciliation. These warnings do not log raw dependency error messages.

The database initializer enables pgvector as the administrative role, and migration
029 validates its version and schema. Runtime application roles remain unprivileged.
The index builds transactionally during a coordinated upgrade before the worker
starts, with the migration startup budget extended to ten minutes. Existing rows
are read to build the index; they are not replaced or re-embedded. The build blocks
chunk writes and rolls back atomically on failure. It is not an online concurrent
build; PostgreSQL does not allow `CREATE INDEX CONCURRENTLY` in the migration
transaction. See [deployment guidance](../../development/compose.md) for retained
volumes and externally managed databases.

The Flutter client uses these operations for its paginated collection and document
workspace. File selection and drag/drop upload UI remain a separate feature.

### Search filters and stable ordering

`POST /api/v1/documents/search` requires `query` and `mode`. Empty trimmed full-text
or hybrid query lists all documents satisfying the other criteria; empty semantic query is
invalid. A nonempty punctuation-only full-text term has no matches. Full-text uses
`websearch_to_tsquery('simple', ...)`, including metadata-only documents and current
lexical chunks while semantic indexing is pending or failed.

Optional `kinds` accepts up to three values from `document`, `letter` and `email`.
A document can match any selected kind. Empty, omitted and all three kinds mean
unrestricted. Duplicates and order normalize to the same effective selection.
Kind refers to stored metadata; PDF and image attachments retain their own kind
when their parent email is excluded. Effective kinds bind cursor fingerprints;
unrestricted requests preserve existing fingerprint bytes.

Tags require every normalized tag. Optional sender and recipient values are
literal, case-insensitive substring filters, bounded to 320 Unicode scalars and
1,280 UTF-8 bytes. Recipient matches each To, CC or BCC entry independently.
`strpos(lower(value), lower(parameter))` with `pg_catalog.pg_unicode_fast` has no
SQL wildcard interpretation, accent removal or Unicode normalization. Kinds,
tags, sender and recipient filter categories combine with AND.

Independent `senderMatch` and `recipientMatch` fields default to `contains`.
Vocabulary selections use `exact`, comparing the complete PostgreSQL Unicode
lowercase value. An invalid explicit mode fails even without an address; a valid
unused mode normalizes to contains. The shared SQL predicate applies before
full-text ranking and semantic candidate selection, and to counts and pages.
Contains-only search cursors retain their original version-one fingerprint bytes;
exact modes append only their effective fields to the fingerprint.

### Library metadata vocabulary

`GET /api/v1/documents/vocabulary` requires both `documents:read` and
`documents:search`. The library comes only from the authenticated session. The
document container injects a dedicated vocabulary service, repository and source
port; the existing document datasource owns its complete SQL transaction.
The vocabulary service rechecks both current claims, membership and session before
calling the scoped repository. The data source decodes and validates the cursor. Its context is bounded to ten seconds, with five-second
statement and lock timeouts.

The `field` is `tag`, `sender` or `recipient`. Optional `query` is a literal
case-insensitive substring, with empty meaning all values. Valid UTF-8 is checked
before Go whitespace trimming, then the normalized query is bounded to 320
scalars/1,280 bytes without controls. Only the four exact query names `field`,
`query`, `limit` and `cursor` are accepted once each. Invalid percent encoding,
malformed UTF-8, unknown aliases and repeated parameters fail. Explicit empty
query is legal; explicit empty cursor and invalid limits fail. Default limit is
40 and the maximum is 50. Authentication precedes all operation validation.

Lookup includes all live documents in the library, independently of active
document filters. Tags preserve exact stored canonical values. Addresses include
nonempty senders or the union of To, CC and BCC, grouped by PostgreSQL
`lower(value COLLATE pg_catalog.pg_unicode_fast)`. Each address group uses its
smallest `C`-collated display string. No accent removal, casefold or Unicode
normalization is added. The repository hashes field, NUL and the exact database
comparison key with SHA-256, so changing an address's display case retains its
opaque identity. Search receives the original selected value, never this key.

Pages contain `items: [{key, value}]` and optional `nextCursor`, without a total.
The datasource groups, orders and seeks using the same explicit Unicode collation,
then fetches one extra value. The bounded shared cursor codec carries the last
returned original value and binds operation `document-vocabulary`, field,
normalized query, library and limit. Address seeks lowercase that original
boundary in PostgreSQL, so representative changes or deletion do not break the
position. These are live positions: new values before the boundary require a
fresh lookup. There is no cap on the library's searchable vocabulary.

The six sort values are `relevance`, `newest`, `oldest`, `title`, `date-newest`
and `date-oldest`. Nonempty queries default to relevance; empty queries default
to newest and reject explicit relevance. Every order includes a UUID tie-breaker.
Dates without a value sort last in both directions. Title uses the database's
Unicode lowercase/code-point order, with the same explicit collation for the
selected key, ordering and seeks. Snippets remain bounded plain text, not HTML;
the summary does not disclose complete metadata, storage paths or OCR.

Search summaries may include an `original` descriptor with only SHA-256, supported
media type and byte size. The existing `documents:search` claim authorizes this
summary independently of document-read and download claims. Original bytes still
require the separate download endpoint and authority. An omitted descriptor makes
no claim about whether an original exists. Both ranking modes first select a bounded
page, including the extra continuation row, then join file records by namespace
and document ID. This preserves ranking, cursor keys, counts and fileless results.
The encoded search response retains its 512 KiB cap.

### Cursor pagination

Both document browse and search accept an optional nonempty `cursor` and return
`nextCursor` only when another row exists. Existing limit/offset requests retain
their defaults and ordering; cursor with positive offset is invalid, while
explicit offset zero is supported. Count and page use one repeatable-read
transaction. Total counts the complete matching set before the seek boundary;
the page fetches one extra row to detect continuation. Browse remains a read-only
transaction scoped by the service's freshly authorized account. Browse requires
`documents:read`; search requires `documents:search` through the identity service
before its content query. A cursor changes neither authorization model.

The shared `data/postgres/pagination` helper owns bounded canonical base64url JSON,
strict object decoding, versioning and fingerprints. Document adapters own typed
keys and parameterized seek predicates. Tokens bind namespace, operation,
normalized term/mode/filters, resolved sort, page size and the captured embedding
space for nonempty hybrid and semantic queries.
They reject malformed Unicode, duplicate/extra/missing/null fields, wrong types,
noncanonical UUID/float/timestamp/date keys and mismatched requests. Limits are
4,096 encoded bytes and 3,072 decoded bytes. PostgreSQL timestamps preserve six
fractional digits; relevance preserves exact finite float8 values. Lowercase
title keys allow 400 scalars/1,600 bytes, including legacy non-NUL controls.

Tokens are unsigned positions, not credentials or confidential values. Forging a
valid position can skip within an authorized query but cannot select a namespace
or inject SQL. They are not multi-request snapshots: edits can move records across
page boundaries. Encoded ordering values still work after the boundary row is
deleted. Neither tokens nor query text belong in routine logs.

Identity lists can adopt the codec with their own normalized fingerprints,
ordering keys, authorization and transactions. This feature leaves those APIs
unchanged and does not introduce a generic repository framework. The
[search API tests](../../../backend/tests/e2e/search_test.go) exercise the protocol
against the compiled backend and real storage.

## Exact OCR and corrections

`GET /api/v1/documents/{id}/ocr` requires both `documents:read` and
`documents:ocr:read`. It returns exact effective text, a nonnegative revision,
its machine/manual origin, and semantic indexing state. A nullable manual text
column distinguishes no correction from a deliberate empty correction. Machine
text and manual text remain separate, so retry cannot replace a saved correction.
Metadata-only documents report `no_original`. Pending or failed extraction reports
`processing` or `processing_failed` when canonical text is absent. Older ready
documents without canonical machine text report `legacy_text_missing`; overlapping
historical chunks are never presented as exact text.

`PUT` on the same route additionally requires `documents:ocr:update`. The body
contains only a required `revision` and `text`. Malformed UTF-8, NUL, unpaired
Unicode surrogate escapes, nulls, duplicate/unknown fields and trailing JSON are
rejected. Decoded text is limited to 2 MiB and 2,048 derived chunks. The JSON
body has a dedicated 12,587,008-byte limit to allow worst-case escaping. Other
JSON limits remain 32 KiB. The stored string retains its exact bytes; only search
chunks normalize controls, line endings and surrounding whitespace. Empty and
whitespace-only text is valid and requires no embedding inference.

Each correction reads current authority, locks document and processing state, checks
the observed revision, and atomically advances revision and processing generation.
It replaces lexical chunks, clears obsolete embeddings and errors, and binds the
new generation to the effective OCR revision. A stale revision or metadata-only
write returns 409. No text or vectors enter Temporal history. The existing
`DocumentIngestionRequest{accountId,documentId,generation}` history shape is unchanged;
activities load the revision binding from PostgreSQL and recheck it on writes.

| Original | Derived chunks | Result | Durable work |
| --- | --- | --- | --- |
| Staged | Nonempty | Queued, embedding | Embed, then promote and publish |
| Final | Nonempty | Queued, embedding | Embed, then publish |
| Staged | Zero | Queued, finalizing | Promote and publish |
| Final | Zero | Ready, complete | None |

Required work is inserted in the existing outbox in the same transaction.
Extraction skips a generation already advanced to embedding or finalization;
embedding skips zero-chunk finalization. Machine acceptance saves exact output,
retains any manual override and advances the effective revision only when machine
text is effective. Replay cannot overwrite newer work. Invalid machine Unicode
or NUL fails with a sanitized processing code rather than rewriting the text.

Full-text search uses current-generation chunks immediately, including during
reindexing or after index failure. Semantic search requires the current revision,
ready processing and completed vectors. OCR reports `pending`, `ready`, `failed`,
`unavailable`, or `not_required` indexing independently of text availability.
The original's storage location remains independent of reindexing state. Saving
the retained correction with its current revision retries semantic indexing.

Processing retry accepts failed documents and ready documents missing canonical
machine text. It refuses pending work and other ready files. It advances the
generation, clears vectors and rebinds retained chunks before extraction, keeping
manual corrections lexically searchable throughout recovery.

## Authorized deletion and retained cleanup identity

`DELETE /api/v1/documents/{id}` requires `documents:read` and `documents:delete`.
The service rechecks both claims. One scoped transaction locks the document then processing,
inserts file cleanup identity, and removes outbox, chunks/vectors, processing,
file records, upload reservations and document text/metadata. It returns 204 at
commit. Missing and foreign documents return the same 404. Metadata-only deletion
does not create a file cleanup record.

Existing-document mutations and worker publication lock document, processing and
child rows in that order. Actor authority checks are ordinary MVCC reads. Outbox
leasing and reconciliation select live
documents using bounded, skipping locks before updating their processing/children.
The SQL data source owns publication through an injected `DocumentPublicationStore` port,
implemented by filesystem storage and wired in bootstrap. It verifies the live
generation and revision before promoting staged files under the transaction's
locks. Already-final files do not need another copy.

Database transactions cannot make filesystem writes atomic. A lost connection can
release the lock while promotion is still completing. A separate cleanup table
therefore retains only server-chosen namespace, uploader and document UUIDs plus
scheduling and lease fields, without document or identity foreign keys. It stores
no filename, hash, OCR or metadata. The reaper leases at most 20 due deletions,
removes staged and final originals plus promotion temporary files, and acknowledges
only its own unexpired lease. Success reschedules the retained record five minutes
later; failure uses bounded exponential backoff. Due-time ordering and leases
prevent successful old records from starving new deletions. Cleanup has a separate
three-second budget within reconciliation so job health checks still run.

Cleanup records remain indefinitely in this version. Later sweeps remove a file
recreated by delayed publication, including after a prior successful sweep.
Logical API removal is immediate at commit; physical erasure is eventual while
storage and the reaper run. A response already transmitted cannot be recalled.

## Jobs, configuration events and reindex batches

`documents:jobs:read` exposes generation history for the current namespace;
`documents:reindex` permits a full reindex of that namespace. Both belong to the
namespace Admin bundle and the owner catalog. Either capability can inspect the
namespace pipeline and aggregate batch progress. The separate system processing
claim manages settings, system batches and the configured dashboard link, without
granting namespace jobs or document content.

Jobs record upload, retry, OCR correction, reindex and legacy generations with
immutable snapshots and honest stage/timing evidence. They survive document
deletion; active deleted generations become cancelled. History has no copied
content or title. An authorized history query joins the current document once
and returns its current title only with `documents:read`; deleted or unreadable
documents return null titles. Strict cursors bind operation, explicit scope, page
size and every filter. A copied ID or cursor never grants authority.

Manual batch request UUIDs are durable idempotency keys bound to requester, scope
and target revision. Identical retries recover the same batch before checking
whether that target revision is still current. Foreign collisions return 404;
conflicting owned input and active equivalent requests return 409. Settings
accept optional `expectedRevision` for older clients: identical values are always
a no-op, while a changed value with a stale supplied revision conflicts.

One database event sequence orders committed document acceptance, new generations
and batch cutoffs. Creators obtain it while holding the schema-scoped processing
coordination lock through commit. Enumeration reads at most 100 documents before
a cutoff and persists every item before advancing its cursor. Missing originals
and deleted documents are skipped. Waiting items rotate independently of locked
or active documents. Ordinary admission alternates with reindex admission, and
batches rotate by service time. Item changes mark their batch for separate
aggregate reconciliation; publication establishes success, not dispatch.

A manual request requires full extraction from the original after its cutoff.
Matching full-ingestion work can satisfy overlapping requests; OCR-only correction
cannot. Automatic work skips an already-ready original only with matching machine
extraction evidence and indexing configuration. Extraction updates exact machine
text and its fingerprint/event provenance atomically. Corrections preserve that
evidence and the exact manual override, including empty text. Every full reindex
extracts again, then indexes the effective manual-or-machine text.

Configuration fingerprints use a versioned, fixed-field canonical encoding with
sorted unique OCR weights. Readiness, timestamps and event/manifest revision
numbers are excluded. Immutable configuration revisions preserve A → B → A
changes. The monotonic installed-manifest revision prevents older or conflicting
binaries from creating or admitting work or passing readiness. Adoption repairs
actual snapshot/provenance drift; unchanged failed or ambiguous legacy snapshots
are not automatically retried. Migration retains one honest legacy generation,
without inventing prior history or start times. Unknown extraction evidence for
legacy manual corrections is treated conservatively.

## Admission ownership and lock order

The retained execution ledger proves ownership for the shared resource scheduler. Under document coordination and the scheduler lock, admission reserves all required resources and records execution ownership in the same transaction. The singleton admission row retains scheduler fairness
state. The ledger has no foreign keys to accounts, users, documents, processing or
jobs. Deletion and supersession cannot remove a possibly running execution’s
ownership. A newer generation of the same document waits for the previous
execution to close. Legacy executions drain independently, and all must close
before new admission.
The original ingestion v1 name and command sequence remain compatible. New
inputs add an optional unlimitedInference flag; old inputs omit it and retain
their original deadlines.

Before an ExecuteWorkflow call, SQL persists a unique lease and a start permit of
at most five seconds. The first permit fixes the retry cutoff at the earlier of
the delivery deadline and 23 hours 59 minutes later. Retries cannot extend it.
Each RPC ends within its persisted permit and uses the reserved workflow and task
queue. Known runs use Describe only. After the retry cutoff no further start call
is allowed. For old bounded executions, missing history is inconclusive until
the latest possible permit end plus the 15-minute execution timeout. A later
NotFound can then permit fenced closure. Unlimited executions cannot use that
elapsed-time proof and retain capacity when their history is missing. Transport
failure always retains capacity. Closure preserves
already-terminal history, fences unfinished work and releases the slot atomically.
A separate bounded SQL sweep expires undelivered work and old bounded processing
during Temporal outages; it does not expire started unlimited processing.

Ordinary document acceptance and generation changes hold a shared transaction
advisory barrier before allocating event sequences or locking their document,
processing and history rows. Independent writers can share this barrier. Batch
cutoff creation, configuration changes, startup and scheduler maintenance use the
exclusive barrier. This prevents an enumeration cursor from passing an acceptance
that has allocated a sequence but has not committed. No transaction upgrades a
shared barrier to exclusive. Operator adoption takes the exclusive barrier before
its account row lock; ordinary inserts rely on PostgreSQL's foreign-key checks.

Only startup initializes and adopts processing configuration. An already adopted,
compatible configuration is a no-op. Routine generation preparation reads the
verified configuration without locking or rewriting its singleton or history.
Scheduler paths begin with exclusive coordination and never acquire authority
rows, even implicitly through history references. Worker transitions and actor
deletion lock document then processing/history; they never lock coordination,
configuration, admission or batches. Configuration reads after document locks are
ordinary MVCC reads. Scheduler transactions perform no inference or Temporal RPC.

Explicit request mutation locks are confined to invariants: partial metadata
merges, document/generation publication, upload reservations, and import
provider/run/item ownership and cancellation fences. The scheduler retains its
admission, delivery and reconciliation locks. Ordinary SQL writes also acquire
PostgreSQL's normal target-row and referential-integrity locks.

History is retained while its namespace exists. A bounded orphan sweep removes
jobs and items whose namespace no longer exists, clears deleted requester IDs,
and aggregates the exact affected batches through item change markers. Execution
ownership remains until verified closure even if the namespace has disappeared.

The optional, instance-wide LLM stage runs after searchable publication in the
downstream AI pipeline. Retained combined generations keep their original stage
order. See [property extraction](property-extraction.md) for settings,
credential storage, generation fencing and provider bounds.

## Password-protected PDFs

A PDF that requires a password remains available with failure code
`encrypted_pdf`. The namespace claim `documents:unlock` permits
`POST /api/v1/documents/{id}/unlock` with the observed generation and password.
Owners receive the claim; admin and user role bundles include it. Passwords are
bounded to 1,024 UTF-8 bytes, preserved exactly, and never persisted or sent to
Temporal. The private processor receives them through the request body and child
stdin. PDFium saves with security removed and verifies reopening without a password.
Wrong passwords return `invalid_pdf_password` without mutating stored content.

The storage adapter syncs a private immutable `unlocked-<SHA256>` candidate in the
existing document directory under final storage. A SQL transaction rechecks the
claim, locked state, generation and original hash; it publishes location
`unlocked`, the new size and hash, and a new ingestion generation with its outbox.
The filename, document ID, metadata and uploader remain unchanged. The normal
publication step keeps this location; staged cleanup retires the encrypted source
after ingestion succeeds. Download and preview identities use the new hash.

An interrupted or rejected publication leaves the old reference usable. Candidate
files left by rejected or uncertain requests stay private and are removed by the
persistent document deletion cleanup, including candidates written after deletion.
No password is stored for retries; users may resubmit after reading current state.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
