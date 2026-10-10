# Data and privacy when hosting Domabas

Domabas stores your library on the infrastructure you configure. Default Compose
services process documents with the private document processor and Ollama.
Administrators can connect other AI services. Review these data flows before
importing sensitive documents or selecting a provider.

## Where data lives

These are the default [Compose](compose.md) locations. Custom deployments can use
different roots or separate hosts; [TrueNAS](../../truenas/README.md#2-prepare-the-dataset)
maps them into your chosen dataset.

| Data | Location |
| --- | --- |
| Originals | `document_ingestion` at `/data/ingestion` holds staged uploads; `document_storage` at `/data/documents` holds finalized files. Accepted documents retain originals after processing failure. Unlocking a PDF stores a decrypted copy here. |
| Library and accounts | PostgreSQL's `domabas` database holds users, email addresses, permissions, metadata, extracted/corrected text, search chunks and embeddings, invoice fields/source XML, thumbnail JPEGs, integration settings and job/import history. |
| Credentials | Account passwords are hashed; server sessions store token digests. IMAP usernames/passwords, Paperless tokens and document/chat provider keys are encrypted database records. Endpoint addresses and other settings are ordinary records. |
| Conversations | PostgreSQL holds messages, titles, accepted model settings and tool snapshots, including document metadata/excerpts/text used by chat. Application permissions scope conversations to their user and library. |
| Encryption keys | `credential_keys` at `/var/lib/domabas/secrets` holds `email.key`, `paperless.key` and `llm.key`. Chat uses `/data/documents/.secrets/chat.key`. Retain configured environment key overrides and historical email keyring entries too. |
| Workflow history | PostgreSQL's separate `temporal` and `temporal_visibility` databases hold operational history. Workflow payloads use identifiers, progress and failure codes; activities load private content from application storage. |
| Scratch and models | The processor temporarily stores original bytes and OCR work, normally removed on completion/shutdown. A hard crash can leave scratch until container recreation. Tesseract and Ollama model caches persist in separate volumes. |

Clients also hold data. Browsers use an HttpOnly session cookie; native clients
use platform-protected credential storage. Server addresses and preferences
persist locally. Mobile scan drafts, page images and prepared PDFs stay in private
application storage and survive sign-out for the same owner, without additional
app-level encryption. Downloads and operating-system copies need separate
protection. See [client storage](../arch/frontend/platforms.md#persistent-session-storage)
and [scan drafts](../arch/frontend/scanner.md).

## What other services receive

**Android document scanning** uses Google ML Kit through Google Play services.
Google processes the scan images on the device and does not send the images or
scan output to its servers. The SDK can download resources and sends usage and
performance metrics to Google. Its [terms and privacy description](https://developers.google.com/ml-kit/terms)
explain this separate data flow. Domabas uploads the saved PDF to the configured
library only when the user submits the draft. iOS retains its custom camera and
system Vision detector.

The backend sends original bytes to the configured **document processor** for
extraction, OCR and thumbnails, and the supplied PDF password when unlocking.
Extracted text passages and semantic-search queries go through that processor
to its configured **Ollama embedding service**. These are local Compose services
by default; configuring another host moves those requests there.

**Document AI** sends bounded extracted or corrected text, instructions and an
output schema to the selected model for enabled property or invoice AI. This
can include names, addresses and payment details. The AI provider receives text,
rather than the original PDF/image. **Chat** sends the question, bounded history
and authorized document-tool results, including metadata, excerpts or text.
External connections send their configured bearer key for authentication.
Review the provider's handling, retention and training terms; Domabas does not
control or erase its copies. See [document AI](property-extraction.md) and
[chat](../arch/backend/ai-chat.md).

Document AI and chat have separate settings. Disabling them does not disable OCR,
structured invoice extraction or Ollama embeddings. Already accepted work keeps
its saved configuration. Startup can download missing OCR/embedding models;
local chat/document AI can download a missing selected model. Choosing local
models alone is not an offline-network guarantee.

Email and Paperless imports contact their configured source with supplied
credentials and retrieve content. Accepted imports can continue after sign-out.
Imported documents become library documents; source systems keep their own copies.

## What deletion removes

Deleting a **document** removes its active metadata, OCR/corrections, text chunks,
embeddings, invoice records and thumbnail bytes from application tables.
Background cleanup removes staged/final originals and decrypted PDF copies;
this requires a running backend and writable storage. Job history,
cleanup/execution identifiers and import evidence can remain. Document deletion
does not scrub earlier chat messages or saved tool snapshots containing its text.

Deleting a **conversation** hides it and prevents further answers being
published. After its background executions close and drain, cleanup scrubs
messages, tool snapshots, source records, title and per-turn endpoint/key
references. Minimal identity and execution records remain; unfinished execution
cleanup can delay scrubbing. Deleting an **email provider** clears its encrypted
credentials and stops further imports, while accepted documents and nonsecret
source/run records remain.

There is no general automatic expiry policy for documents or application job
history. New Temporal namespaces use 72-hour closed-history retention; existing
namespaces retain their configured setting. This does not expire application
records. Deletion does not erase earlier downloads, logs, database recovery files,
snapshots, backups or provider copies, and is not secure disk erasure.

## Encryption, logs and backups

Credential encryption protects selected database secrets. It does **not**
encrypt all documents, text, chat, thumbnails, logs or volumes. The running backend
can decrypt integration credentials. Operators must provide disk/dataset and
backup encryption where needed, restrict host/database access and protect devices.
Use HTTPS for clients and protect internal traffic; bundled private connections
use HTTP or unencrypted database/Temporal connections.

**Current logging limitation:** native Ollama document-AI requests write the full
sent prompt, including document text, and model response JSON to backend INFO
logs. This applies to property/invoice inference, not the separate chat or
external-provider diagnostic paths. Treat backend/container logs and forwarded
copies as sensitive document data; manage their access and retention.

Arrange consistent backups of PostgreSQL's application **and Temporal** data,
staged uploads, documents and every credential key/override, with private
deployment configuration. Protect keys separately while retaining their
association with the matching database backup. A lost key makes saved credentials
unreadable and can prevent startup; a new key cannot decrypt old records.
Model caches can be downloaded again; originals and keys cannot be recreated
that way. Retained volumes are not independent backups.
See [storage and recovery](../arch/backend/postgresql.md#files-keys-and-recovery)
and [TrueNAS backup guidance](../../truenas/README.md#update-and-back-up).
This guide does not establish a tested restore procedure.
