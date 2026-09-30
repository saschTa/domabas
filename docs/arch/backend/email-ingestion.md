# Email ingestion and personal activity

The deterministic polling definition is
`domain/email/workflows/email_poll.workflow.go`. `EmailPollActivities` and
`EmailPollDispatcher` live in `data/email/temporal`, with injected service ports.
The registered names remain `domabas.EmailPoll.v1` and `domabas.EmailPollPage.v1`;
payloads retain their original field names and page limits.

The email domain owns private IMAP providers, scheduling, mailbox progress and
retrieval outcomes. Its consumer-owned import port receives the injected document
application service. Document
owns original files, MIME interpretation, metadata, processing and source links.
Identity owns the user's activity read model. None of these domains depends on
another domain's concrete source, repository, handler or container.

Both personal and per-provider run histories accept optional status filtering.
SQL applies the filter before the bounded keyset page. Cursors bind status,
provider, owner, library and page size; unfiltered cursor encoding stays compatible.

## Ownership and background consent

A provider belongs to one user and one immutable destination library. The
`email:manage` namespace claim permits managing that user's providers; it does
not expose another member's mailbox. Enabling import also requires current
document-read and upload claims. System administration supplies no mailbox access.

Enabled providers continue after logout. Background consent records the owner's
identity credential revision, so a password change requires explicit renewal.
Ordinary settings saves preserve a renewal requirement. Disabling, deleting or
editing a provider fences work using its previous revision. Each acceptance checks
the current provider, user, membership, claims, generation and activity attempt.
Background authority contains durable IDs and fences, never a bearer or invented
session.

The acceptance commit is the retention boundary. A committed email or attachment
is an ordinary library document; later provider deletion or membership changes do
not delete it. Later service stages reject unaccepted work whose authority has been revoked. Deleted sources retain
nonsecret identity evidence so routine polling does not recreate their documents.

## Credentials and IMAP transport

Both username and password are encrypted in a versioned AES-256-GCM envelope.
Associated data binds the envelope to provider, owner and library. The injected
keyring identifies an active write key and retained read keys. Rekeying uses a
compare-and-swap against the unchanged envelope and credential version, without
renewing consent or overwriting an edit. Passwords are never returned; only the
authorized owner may retrieve the username for editing.

Without explicit keyring configuration, first startup generates a separate random
32-byte key in `DOCUMENT_STORAGE_ROOT/.secrets/email.key` with private permissions.
`EMAIL_CREDENTIAL_KEY_FILE` can change that path. Complete temporary files are
synced and published exclusively; concurrent startups cannot overwrite a key or
read partial contents. Later startups reuse the file. A bounded startup transaction
locks the provider table against writes while checking retained envelopes. Missing,
invalid, insecure or incorrect automatic key files fail startup when credentials
cannot be recovered; they are never silently replaced.

Explicit keyring configuration takes precedence and retains existing key rotation
and missing-historical-key recovery behavior. Invalid or partial supplied
configuration fails startup without echoing secrets. Compose persists the automatic
email key beside the separate Paperless key in its retained credential volume.
Replicas sharing a database must share their key file or explicit keyring. Keep
the keys with installation backups, separately protected from database backups.
Deployment setup is described in the
[email configuration guide](../../development/email.md).

The adapter uses verified implicit TLS and a configurable port, default 993.
An optional CA file adds private trust roots while preserving hostname validation.
Public destinations are available by default; private destinations require an
explicit hostname allowlist. Resolution and dialing use the same validated IPs.
The adapter rejects the whole DNS answer if any address violates that policy.
DNS resolution and TCP connection attempts share a ten-second budget, bounded
by the caller's earlier deadline. Each candidate receives a share of the
remaining time, so an unreachable first address does not consume the entire
budget. Fallback dials numeric addresses without another DNS lookup. TLS still
verifies the configured hostname; a TLS failure stops connection setup.
Connections have deadlines, cancellation closes sockets, and cleanup joins reader
and heartbeat work. Connection tests use read-only mailbox selection and do not
advance import state or change message flags.

The pinned IMAP client streams BODY literals. An adapter guard limits decrypted
bytes, frames, tokens, literals and nesting before upstream parsing. Its large
literal exception applies only to the exact streaming full-BODY response context;
other literals stay small. A UID returned after its body is validated before any
acceptance.

## Durable mailbox progress

Source identity includes provider, source generation, mailbox generation and UID.
Mailbox generations retain UIDVALIDITY; Message-ID remains optional metadata.
Endpoint, login or mailbox changes create new source generations. Old pending
items become ineligible immediately, while accepted evidence remains intact.

Discovery captures a finite UID upper bound and examines windows of at most 1,000
existing messages. Read-only sequence UID probes locate each window without
walking gaps in numeric UIDs; only UIDs are persisted. An EXPUNGE after selection
invalidates positional discovery and retries with a fresh session before any
uncertain checkpoint is returned. Search identities and cardinality are validated
before expansion. Discovery uses INTERNALDATE for exact maximum-age checks and
BODY.PEEK to avoid setting Seen. A window advances only through durable items or
known empty ranges. A page ending within a window advances only through its last
selected UID. Separate
live and backfill cursors let a wider age setting revisit older mail while new
mail continues to progress. Due pending items rotate with bounded retry delays.

An outer envelope passing the raw-file bounds is accepted unchanged before
attachment inspection. Invalid optional headers use safe metadata fallbacks.
Body extraction, attachment inspection and individual parts have separate
outcomes: a damaged subtree cannot discard a retained original or claim complete
attachment discovery. Supported PDF, PNG and JPEG parts enter normal ingestion.
Unknown or unsupported parts have explicit dispositions.

Part identities use MIME paths. Acceptance atomically records a source-part link,
document metadata, original file and ordinary document outbox. Namespace byte-hash
deduplication may reuse an existing document. Consequently one attachment can
have several email parents; parent links are paginated and deduplicated by live
document identity. Reindexing an email does not import its attachments again.

## Transactions and worker lifetime

Ordinary authority checks read user, membership, claims and the optional HTTP
session together without locking identity rows. Provider and history reads use
read-only repeatable-read snapshots. An operation authorized before revocation may
finish; each later service operation checks authority again, including background
work. The authority read precedes the scoped content snapshot.
Creating a provider takes an owner-scoped advisory lock around the provider count
and insertion, preserving the limit of twenty across libraries.

Mutations retain narrow provider, run/generation, document coordination, source
part, document and processing locks for revisions, cancellation and attempt
ownership. No database locks span IMAP, parsing, bulk file
I/O or Temporal calls. Document publication and deletion never return to provider
locks. Scheduler metadata avoids identity/document foreign keys that would create
an implicit reverse lock.

The email worker uses a separate schema-specific task queue, ten concurrent
activities and a durable capacity of ten unclosed executions across Go instances.
Admission locks the singleton coordination row before counting and reserving
execution records. One current run per provider and persisted outbox intent prevent overlapping
schedules from duplicating work. Temporal inputs and heartbeats contain IDs and
bounded progress only. Attempt tokens and deadlines fence stale retries; each
unaccepted attempt has its own staging reservation. Conditional cleanup cannot
remove another attempt's accepted original.

Retained execution ownership, bounded start permits and a retention-aware retry
horizon handle ambiguous starts. Completion of database work does not release the
capacity before Temporal closure is established. Document processing retains its
own independent capacity of ten. Both workers and dispatchers stop and drain before shared Temporal,
storage and PostgreSQL resources close.

## EML extraction and activity

`GET /api/v1/email-runs` exposes bounded retrieval history for the authenticated
owner in the current library, including deleted providers. It requires
`email:manage`, binds cursors to owner/library and collection scope, and never
returns credentials. Fatal retrieval failures preserve the last recorded stage
instead of replacing it with complete, so job details can identify where work
stopped. Per-message and attachment failures remain separate aggregate outcomes.

`message/rfc822` originals use bounded MIME parsing and safe plain text. HTML-only
bodies become text without scripts, remote resources or embedded browser content.
Actual MIME extraction evidence is separate from configured image OCR evidence.
The current extraction manifest supports EML while retained v1 PDF/image snapshots
and their fingerprints remain interpretable. Manual text corrections retain their
existing revision and indexing behavior.

The `activity:read:own` claim exposes attributable work across currently authorized
libraries. A read-only repeatable-read transaction validates the session and each
library's current membership/claims before ordering the combined feed. It returns
up to 20 active jobs and five finished jobs per page across email retrieval,
user-initiated document processing and requested namespace reindex batches.
Active and finished lists have independent scoped cursors using timestamp, kind
and ID as their stable order. Each continuation rechecks authorization.
Batch children are not duplicated. Automatic or unattributable legacy work has no
invented user ownership. Titles and links require current access to live records.

See the [email interface](../frontend/email.md) for user-visible progress and the
[testing guide](../../development/testing.md) for real-service validation commands.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
