# Private AI chat

AI chat starts disabled. Admin settings → AI chat accepts an OpenAI-compatible
API base URL, a model identifier and an optional bearer secret. Saving settings
does not run inference. The independent **Enable thinking for chat** switch
defaults off and is stored in configuration and accepted-turn columns. Omitted
updates retain the saved choice. Only future accepted turns use the new revision. Disabling chat preserves history and previously accepted external work.

The external provider manages its context window. Domabas caps the history and document text attached to each request. Upgrades preserve existing external configurations and turn history. Migration 044 disables legacy internal connections and marks their queued or running turns as failed with `configuration_unavailable`. It releases their worker reservations and leases. Earlier messages retain their original provider and model. An administrator can enable new turns by saving an external URL and model.

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

The native worker processes admitted turns using the stable turn identity. Each provider round has an ordinal and a checkpoint. The chat service recognizes completed answers and persisted tool results on retry. The execution ledger contains identifiers and progress. Private messages stay in the chat tables. A random execution token with a renewable 180-second lease fences
stage, tool and final writes. Renewal runs every five seconds. Provider calls are
cancellable and bounded to 30 minutes; each round has a durable checkpoint. Deleting a conversation hides it and
fences publication while retaining the records needed to reconcile background
work. After every owned execution has closed and drained, deletion scrubs message
text, tool snapshots, sources, titles, hashes and per-turn endpoint/credential
references. Minimal identity and execution tombstones remain for reconciliation;
unused credentials are removed. Cancellation confirms the database fence immediately; the owned request
then drains. “Send again” creates another visible prompt with a fresh request ID.

The [shared scheduler](resource-scheduler.md) admits chat turns and grants model and provider slots around each provider call. External origins use separate limits from local embeddings. Running requests do not poll or cancel when ingestion arrives. Chat document tools use lexical search and create no embedding requests. Missing optional chat models do not make the application unready, but failed workers and dispatchers do.

## Model callbacks and context

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
to the shared reasoning/final-output generation cap on the provider.
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
only when requested. Domabas validates tool arguments locally.

External calls use temperature 0.2.
External requests send `reasoning_effort: medium/none` for enabled/disabled
thinking, including tool rounds and the final answer-only request. LM Studio
0.4.8+ supports this field without an extra compatibility mode; see its
[changelog](https://lmstudio.ai/changelog/lmstudio). Support depends on the selected
model and provider; mandatory reasoning models may not accept disabling it.
Unsupported requests are not retried without the preference. Keep LM Studio
reasoning separated from final content. Chat returns `output_limit` when the provider reports a length stop and `empty_response` for a completed reply without final content.

## Verification

Provider and workflow tests cover tool calls, malformed transport,
safe errors, cancellation and reconciliation. PostgreSQL tests cover encryption,
private ownership, fresh authority, idempotency, paging, admission and fencing.
Compiled API and browser E2E use deterministic local providers with real
PostgreSQL. Live model checks use an explicitly configured LM Studio endpoint.
