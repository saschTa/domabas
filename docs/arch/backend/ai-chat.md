# Private AI chat

AI chat is independent of document enrichment. It starts enabled with internal
Ollama and `qwen3.5:4b`. Admin settings → AI chat selects a model from the installed
catalog or an explicit name, or configures an external OpenAI-compatible API base
URL, model and optional bearer secret. Saving settings never runs inference or
changes document processing. The independent **Enable thinking for chat** switch
defaults off and is stored
in typed configuration and accepted-turn columns. Omitted updates retain the
saved choice. Only future accepted turns use the new revision;
disabling chat prevents new turns while preserving history and accepted work.

Administrators choose a requested native Ollama context from 1,024 through
1,048,576 tokens, independently of the document AI pipeline. Current settings
default to 32,768. The typed setting is copied into every accepted turn; retained
turns from before the setting keep 16,384. Omitted update fields preserve the
saved value. An optional administrator model lookup calls `/api/show` without
downloading or running the model. Saving settings does not contact Ollama.

Before native inference, the adapter reads the selected architecture's context
maximum from `model_info`, including after downloading a missing model. It sends
the smaller of the accepted request and that maximum as `options.num_ctx`.
Missing or invalid metadata fails with `configuration_unavailable`. External
OpenAI-compatible services retain their existing wire format and manage their
own context. The setting does not expand the bounded history or document text
described below.

## Authority and storage

The namespace claim `chat:use` belongs to the ordinary admin, user and viewer
role bundles. `system:chat:manage` controls installation settings independently.
Namespace ownership never confers system claims. HTTP guards and explicit chat
service methods enforce current authority. Conversations belong to one user in one
namespace; namespace administrators cannot read another member's conversations.

Ordinary authority checks use one joined snapshot without locking identity rows.
Configuration, conversation and message reads use read-only repeatable-read
transactions without entity locks. An operation authorized before revocation may
finish; every later foreground or background service operation checks again.
The authority snapshot precedes the scoped content transaction. Execution
services select chat and document claims from fresh retained-identity facts.
Conversation/turn mutation locks retain cancellation and execution fencing.
Acceptance takes a shared configuration lock so credential rotation cannot remove
a key before the new turn references it; configuration writes take the conflicting
exclusive lock. Only admission takes the quota coordination lock.

The `chat` domain has its own models, ports, services, data adapters, HTTP routes
and bootstrap container. Operational settings, conversations, messages, turns,
delivery/execution ownership, tool arguments and source references use typed
columns and child tables. Accepted turns retain provider/model/URL/credential
references. AES-256-GCM encrypts credential records with their IDs as authenticated
data. The persistent private `documents/.secrets/chat.key` file is separate from
document AI credentials. Back it up with the database and share it across backend
instances. Startup rejects missing or incompatible keys when ciphertext exists.
Responses, workflow history and routine logs never contain secrets.

An omitted or null replacement preserves the existing key only for the same provider and
endpoint. Changing either clears the key unless replaced explicitly. Model-only
changes retain it. Optimistic revisions prevent overwriting another admin's save.
The ordinary user's configuration summary contains only availability, revision,
provider and model. Replacing or clearing a credential removes its old ciphertext
only when no configuration or accepted turn still references it.

## Durable turns and resource admission

Creating a conversation and sending its first message are separate idempotent
operations. Send commits the user message, assistant placeholder and turn outbox
intent atomically. Reusing a request UUID with different content conflicts. There
is at most one active turn per conversation and ten pending turns per user.
Conversation and message APIs have bounded continuation pages.

`domabas.ChatTurn.v1` uses the dedicated `-chat` task queue. The shared resource scheduler reserves worker and accepted-provider capacity before a turn starts, across all backend instances. Delivery leases reconcile
the stable `domabas-chat-{turn UUID}` identity, workflow type, task queue, input
identity and retained run before accepting an ambiguous start. Starts are bounded
to twenty hours, shorter than required Temporal history retention. Terminal
execution ownership remains reserved until closure and activity drain are safe.

New workflow executions call `domabas.RunChatStep.v1` once per provider round,
with an expected ordinal from zero through thirty. Each step permits four
automatic retries after the first attempt, with 190-second waits that exceed the
execution lease. A persisted tool result completes its ordinal; a lost activity
completion cannot run the next round under the previous retry budget. Atomic
step acquisition recognizes an already-published answer and returns completion
without generating it again. A version marker keeps retained workflows on the
registered whole-turn activity and its previous three-attempt policy. Terminal
provider errors do not retry, and waiting for scheduler admission consumes no activity retry.

Activities load private content from PostgreSQL and return no message contents
to Temporal. A random execution token with a renewable 180-second lease fences
stage, tool and final writes. Renewal runs every five seconds. Provider calls are
cancellable and bounded to 30 minutes; retry delays exceed the activity lease.
Workflows have a 24-hour execution bound. Deleting a conversation hides it and
fences publication while retaining the records needed to reconcile background
work. After every owned execution has closed and drained, deletion scrubs message
text, tool snapshots, sources, titles, hashes and per-turn endpoint/credential
references. Minimal identity and execution tombstones remain for reconciliation;
unused credentials are removed. Cancellation confirms the database fence immediately; the owned request
then drains. “Send again” creates another visible prompt with a fresh request ID.

The [shared scheduler](resource-scheduler.md) atomically admits worker and provider requirements. Internal Ollama aliases share the ingestion embedding pool; external origins use independent pools. Running requests do not poll or cancel when ingestion arrives. Chat document tools use lexical search and create no embedding requests. Missing optional chat models do not make the application unready, but failed workers and dispatchers do.

## Model callbacks and context

Internal Ollama uses a required JSON action schema in a single user
message. It supports `list_tools`, `search_documents`, `read_document`
and `answer`.
External providers use native OpenAI-compatible function calls, one at a time,
with matching call IDs and tool replies. Unsupported, malformed, truncated and
oversized responses become safe error codes. Redirects are never followed.

Tools are read-only. Namespace and actor come from the accepted turn, never tool
arguments. Search and reads recheck current `documents:read`, `documents:search`
and `documents:ocr:read`, membership and user security revision. Current authority
is checked again before inference and publication. Deleted or inaccessible source
content cannot enter a new model request. Sources are recorded from successful
retrievals; model text cannot manufacture trusted document links. The frontend
labels these “Documents consulted”, since retrieval does not prove every claim.

Limits are explicit: 8,000 user-message characters, twenty recent history messages,
48,000 context characters, 64 transcript messages, thirty persisted tool calls,
ten search results per page,
8,000 characters per document read, 500-character excerpts and a 2,048-token
final-output allowance with thinking off. Enabling thinking adds 4,096 tokens
to the shared reasoning/final-output generation cap on both providers.
Older conversation history remains available through API/UI pagination. Tool
continuation uses an offset. Document text is untrusted evidence, separated from
instructions. The exact immutable tool reply is retained as a protocol snapshot
for activity recovery, alongside typed operational fields; see
[persistence](persistence.md).

The final tool result is followed by an answer-only inference request, even after
attempt thirty. Discovery and rejected proposals count toward the same persisted
budget; recovery cannot reset it. Providers receive the remaining budget and a
bounded ledger of previous call arguments and outcomes.

The fenced tool transaction blocks duplicate executions by tool-specific
arguments, ignoring provider call IDs and normalizing search case and whitespace.
Same-ordinal recovery still replays the original reply. Reads require a document
ID returned by a search in the current turn. Positive offsets must match a
returned continuation for that same query, document or catalog. Error codes are
not accepted as search queries. Rejected attempts return corrective feedback and
no document sources. A rejected proposal can be retried after its prerequisites
are satisfied; a previously executed call cannot execute again in that turn.

Typed outcomes and continuation offsets are persisted alongside tool replies.
New search IDs, nonempty new read pages and new catalog pages count as progress.
Empty results, rediscovery of only known documents, unavailable reads and
rejections count as no progress. After three consecutive no-progress attempts,
the next inference is answer-only. A provider that still requests a tool or emits
a malformed final response receives no further execution; the service completes
with a fixed statement that it could not reliably verify the requested facts.
Transport, authority and cancellation failures retain their existing handling.
All stopping state and source provenance survive activity recovery and evidence
eviction. These rules bound bad model planning but do not guarantee that a small
model chooses effective search terms or finds all requested evidence.

The ledger is not factual evidence. Context packing reserves the latest question,
then retains recent complete call/reply pairs and as much older history as fits
both limits. It never cuts a tool result in the middle of its JSON.

`list_tools` returns two descriptions and argument schemas per page, ordered as
discovery, search and read, with `nextOffset` when more entries exist. The catalog
documents lexical search syntax, result fields, continuation and empty results.
It uses `chat:use`, has no document sources and retains the same fenced immutable
reply snapshot as retrieval calls. Retrieval still enforces the document claims.
External providers retain three compact callable schemas; detailed help loads
only when requested. Both provider protocols retain strict local validation.

Both native Ollama and external provider calls use temperature 0.2.
New installations seed `qwen3.5:4b`; upgrades retain existing chat settings and
accepted turn snapshots. The model-column default applies to future rows. The
seed is changed only when chat's creation migration ran in the same transaction,
as identified by its migration-ledger timestamp.

Native inference sends the accepted thinking preference as `think: true/false`.
External requests send `reasoning_effort: medium/none` for enabled/disabled
thinking, including tool rounds and the final answer-only request. LM Studio
0.4.8+ supports this field without an extra compatibility mode; see its
[changelog](https://lmstudio.ai/changelog/lmstudio). Support depends on the selected
model and provider; mandatory reasoning models may not accept disabling it.
Unsupported requests are not retried without the preference. Keep LM Studio
reasoning separated from final content. Structured ai_inference logs contain
task/model, context, input/output
sizes, token counts, timings and safe outcome codes. They never contain prompts,
document text, replies, credentials or reasoning. Separate output_limit and
empty_response errors make reasoning exhaustion visible. Native responses are
bounded to 256 KiB. Chat retrieval and transcript packing are unchanged.

## Verification

Provider and workflow tests cover Qwen actions, native tools, malformed transport,
safe errors, cancellation and reconciliation. PostgreSQL tests cover encryption,
private ownership, fresh authority, idempotency, paging, admission and fencing.
Compiled API and browser E2E use deterministic local providers with real
PostgreSQL/Temporal. `task test:llm` additionally checks the installed Qwen model
when explicitly configured. Test schemas, task queues, storage and workflow
cleanup belong only to each test. See the
[testing guide](../../development/testing.md) for prerequisites and suite commands.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
