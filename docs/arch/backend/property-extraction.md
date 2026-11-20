# Optional document property extraction

System administrators can enable property extraction under Admin → Document
processing. The existing `system:document-processing:manage` claim authorizes
reading and changing this installation-wide configuration. Namespace ownership
does not grant it. The HTTP guard and the SQL transaction both enforce authority.

Property AI and invoice AI have independent switches and default to off. They
share a connection to an external provider. External
providers use an administrator-entered OpenAI-compatible base URL, including the
API prefix such as `/v1`, and an optional bearer API key. Private HTTP services
are supported. The URL cannot contain credentials, a query or a fragment.

External connections offer **LM Studio compatibility mode**, off by default.
Enable it for LM Studio to send the existing task schema through
`response_format.type=json_schema` instead of `json_object`. It applies to
properties, invoice classification and invoice extraction. Administrators select the format explicitly.

Thinking uses the standard external `reasoning_effort` field independently of
JSON compatibility. [LM Studio 0.4.8 and later](https://lmstudio.ai/changelog/lmstudio)
support that field on `/v1/chat/completions`; no additional compatibility switch
is needed. Keep reasoning separate from final content in LM Studio developer
settings. Older versions and models without on/off reasoning controls may ignore
or reject the request. Other external providers must support `none` and `medium`;
Domabas passes the requested preference through to the configured provider.

## Configuration and credentials

The processing configuration revision, optimistic save check and transactional
AI rescheduling intent cover this step. AI-only changes preserve the ingestion
index. The configuration is copied into each accepted AI attempt. A settings save
does no network I/O to a provider. Identical saves retain the revision and create
no work. Startup reads the saved configuration and independently verifies the installed OCR and embedding manifest. Historical snapshots keep their original fingerprints.

AI maintenance acquires its bounded page of document and active-attempt locks
without waiting. A busy row rolls back the whole page and retains the cursor for
the next bounded retry. AI admission and recovery queues skip busy rows and
reconsider them on later polls. Recovery resolution also yields on contention
while retaining its lease and execution ownership. These background operations
do not hold installation-wide configuration coordination while waiting for an
active document write. AI admission uses its own dispatcher lock instead of the
configuration barrier. It reconciles scheduler state once per bounded candidate
page and yields if the scheduler singleton is busy. Ingestion admission also
yields on that scheduler lock while preserving its generation coordination.
AI lease recovery uses exact row/lease fences without the configuration barrier.
Model and invoice/property switch saves therefore do not wait for a
long AI admission transaction. See [resource scheduling](resource-scheduler.md).

`llm.enabled` controls only property extraction. `llm.invoiceEnabled` controls AI
invoice extraction, and omitting it in an update preserves the current value.
Retained internal snapshots without `InvoiceEnabled` keep their original shared
switch behavior. New updates store an explicit invoice choice. The SQL and Go
fingerprints include a separate invoice component when the switches differ;
equivalent legacy configurations keep their existing identity. Job snapshots
expose both switches and the shared model independently.

API keys are AES-256-GCM ciphertext in `document_llm_credentials`, authenticated
with their random record ID. A generation stores only that ID. Replacing or
removing the current key retains the old encrypted record for accepted jobs.
Changing the provider or URL clears its key unless the administrator supplies a
replacement; changing only the model retains it. Keys never appear in API
responses, pipeline snapshots, workflow histories or routine logs.

Startup creates a private, persistent `llm.key` file if no explicit
`LLM_CREDENTIAL_KEY` is supplied. Missing keys with retained ciphertext and keys
that cannot decrypt existing records fail startup. Back up the key with the
database. Multiple backend instances must share the same persistent key or
receive the same base64-encoded 32-byte key through environment injection.

## Execution and publication

After searchable publication, invoice and property extraction can run concurrently. Each branch checkpoints independently and takes its own pipeline slot. Both use the snapshotted connection for inference. Structured invoice XML bypasses inference. The property service
uses consumer-owned repository and extractor ports; HTTP and encryption stay in
document data adapters. Actual model calls acquire shared model and provider slots. Generation and OCR revision fence publication as described in the [document pipeline](document-ingestion.md).

The external adapter sends the configured model and uses temperature 0.2. The provider chooses the context window. The adapter applies the accepted per-step thinking preference and output limits.
The system message contains the instructions and output schema. The user message contains the selected OCR text. Empty
objects and missing properties are rejected. All six keys are required, but each
value may be `null` when unknown. The adapter checks key presence separately from
value decoding, then maps explicit nulls to empty strings or lists in the existing
metadata model. Wrong types, unknown keys and trailing JSON remain errors.
External providers receive
`/chat/completions` with JSON object output (or named JSON schema output in
LM Studio compatibility mode), no streaming and a 2,048-token output
bound when thinking is off, or 6,144 tokens when enabled. External requests send
`reasoning_effort: none` when off and `medium` when on. Calls never follow
redirects. Inference has no fixed HTTP time limit and
remains cancellable. Responses are bounded to 256 KiB. Property extraction sends
the first 100,000 Unicode characters of effective OCR text. Long documents
therefore use an explicitly bounded prefix; later pages
may contain properties this version does not extract. Provider errors become
sanitized failure codes. Failed enabled extraction is visible in Jobs and can be
retried. Empty effective text skips the step.

New installations have both AI steps disabled. Upgrading preserves configured external endpoints and credentials. Migration 044 closes pending internal-provider enrichment attempts with `configuration_unavailable` and releases their leases. Pipeline initialization disables both AI switches on a previously internal connection. An administrator must select an external URL and model before enabling either switch again.
External `ai_inference` logs record provider, task, model, output format, token
counts, elapsed time and outcome. Failures distinguish HTTP rejection, transport,
response reading and response decoding. HTTP status and a safe error category
identify unsupported response formats, context limits and schema rejection.
Only the first 4 KiB of a rejected response is inspected, with a two-second read
limit after rejection; its original text, request URLs, credentials, prompts,
document content and reasoning are not logged. Final content and reasoning
lengths help diagnose model responses with no final answer. API and job failure
codes remain sanitized.

The adapter treats document text as untrusted input and asks for description,
tags, sender, recipients, document date and subject. The concise field prompt
requires English JSON regardless of source language, preserving names, addresses
and identifiers verbatim. It defines the document date separately from the
payment due date and shows conversion to zero-padded `YYYY-MM-DD`; missing,
invalid or ambiguous dates must be `null`. Other unknown or ambiguous values also
use `null`; collections with no supported entries use `[]`. Required keys never
justify inventing facts, using today's date or deriving an absent subject from a
summary. The model is asked to inspect the entire supplied text. Nulls become
empty metadata and cannot replace populated user fields.
It converts whitespace in AI-generated sender, recipient, subject and tag strings
into single spaces so postal address line breaks fit the single-line metadata
fields. Descriptions retain their formatting. The domain still validates lengths, dates, unique list
entries and other control characters with the normal metadata limits.
Publication locks the current document,
generation and OCR revision. It fills empty fields and preserves populated ones;
title and kind always remain as supplied. A metadata revision prevents any result
from applying if a user edits or clears metadata while the model is running.
The stage transition and property publication commit together. Retries cannot
publish properties to a superseded generation or apply the result twice.

Model calls acquire permits for their external provider origin. Local embeddings have independent capacity. See the [shared scheduler](resource-scheduler.md).

Job snapshots expose only whether extraction was enabled and the selected model;
they do not expose the external endpoint or key. Model names are administrator
choices, not immutable evidence of model weights. All existing document sources
(uploads, scanners, email and Paperless) enter the same pipeline.

## Verification

Unit tests cover settings identity and validation, bounded provider transport,
redirects, provider errors and service validation. PostgreSQL
integration tests cover ciphertext, key restoration, permission checks, settings
revisions, SQL/Go fingerprint agreement and metadata/generation publication.
Compiled API E2E exercises restart, another library's ingestion, searchable
properties, failure and retry. Browser E2E configures a deterministic provider in
the real UI and observes enriched properties after OCR and native background processing.

## Independent follow-up processing

Historical snapshots retain their fingerprint and typed configuration values.
The current LM Studio preference is also a typed column. Immutable accepted
snapshots retain it, while older snapshots and missing response fields mean
false. Omitted updates preserve the preference. True adds a fingerprint component;
false preserves existing fingerprints. Changing the preference reschedules only AI.
Independent `propertyThinkingEnabled` and `invoiceThinkingEnabled` preferences
also use typed active columns and immutable accepted snapshots. Both default off;
omitted updates preserve the saved choices. Each true flag adds its own SQL/Go
fingerprint component. Thinking changes schedule only AI follow-up processing.
The bounded OCR text prefix is unchanged; generation budgets increase only when
thinking is enabled.

New ingestion generations finish OCR, embeddings and publication before the AI
workflow starts. Property extraction updates only the current follow-up attempt
and missing metadata protected by its metadata revision; an AI error cannot fail
ingestion. Invoice and property switches remain independent. AI-only settings
saves persist a bounded rescheduling intent and preserve OCR, vectors and search.
An explicit AI retry creates a new attempt under the current configuration without
reindexing the document. Retained combined workflows preserve their original SQL
stages. See [document ingestion](document-ingestion.md) for ownership and migration.
