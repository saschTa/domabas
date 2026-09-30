# AI chat workspace

AI chat is a primary workspace destination requiring `chat:use`. Each conversation
belongs to the signed-in user in the selected library. The separate Admin
settings → AI chat page requires `system:chat:manage`; it edits its own provider,
model and credential configuration without changing the document AI pipeline.

`ChatRepository` exposes immutable chat values. `ChatRemoteDataSource` uses the
contract-generated `ChatApi` with abortable, bounded HTTP requests.
`RemoteChatRepository` and dedicated mappers translate API values and safe
failures. `AuthenticatedDependencies` owns the repository and cancels its requests
when the session or library scope ends. `AccountWorkspace` owns `ChatCubit` and
`ChatSettingsCubit`, gates navigation by claims and manages their visible and
foreground lifetimes. Production uses the actual API.

The chat workspace uses the shared theme and surfaces. Wide windows show a
conversation sidebar; narrow windows and enlarged text use a History dialog.
Conversation and message collections use separate bounded server pages and
explicit continuation. Message refresh merges stable IDs while retaining earlier
loaded messages, history cursors and drafts. Each conversation has a retained
in-memory draft. Returning from another workspace destination keeps that draft;
authentication or library replacement disposes it.

History rows expose a delete action on wide and narrow layouts. Confirmation
explains permanent message removal and stopping an active reply. A pending delete
disables conflicting sends, selection and history requests. Failure keeps the
conversation and draft with a bounded error banner above the scrolling history so
failure remains visible when deleting an older conversation. The user can retry; a missing
conversation on retry is treated as already deleted. Successful deletion removes
its retained draft. Deleting the selected conversation resets the transcript and
composer, while deleting another conversation retains the current selection and
draft. Request epochs fence late history and selected-message reads so a deleted
conversation cannot reappear.

Refresh retains loaded pages and their continuation. When a complete newest page
contains no previously loaded IDs, its continuation becomes available to fill the
gap before the retained history. This also discovers pagination when an initially
empty history gains more than one page of conversations. The same rule applies to
message refreshes; exhausted cursors remain exhausted on overlapping refreshes.
Overlap uses IDs read from server pages; an individually created conversation or
newly accepted message cannot hide an unread gap between those pages.

Sending an initial question first creates an empty conversation, then accepts the
question. Each operation has its own retained request UUID. An uncertain result
keeps the question and offers Check sent message, replaying the same IDs. It
blocks new sends until the result is reconciled. Send again on a failed or
cancelled reply fills the composer with the earlier question; pressing Send then
creates another visible question with a new request UUID.

Persisted stage/status fields drive Queued, Waiting to start,
Preparing, Thinking, Searching your library, Reading documents and terminal
feedback. Queued turns wait for worker and provider resource capacity
without estimating a completion percentage. Private chat notifications refresh
conversations and selected messages while visible and foregrounded. There is no
polling fallback; reconnect establishes a fresh baseline without discarding drafts.
Refresh failures preserve the last successful transcript and show a safe notice.
Stop displays pending cancellation until the API confirms its durable write.

The transcript displays selectable plain text and recorded Documents consulted
buttons. Source IDs enter the existing document viewer through an app callback;
model-authored text cannot manufacture a trusted route. Composer controls respect
keyboard and shell insets. Ctrl/Cmd+Enter sends and Enter inserts a newline. The
transcript preserves the scroll anchor while earlier messages are inserted,
only follows new content when already near its bottom, and offers Jump to latest.

Administrator settings support the internal Ollama default `qwen3.5:4b`, a
paginated installed-model catalog and explicit model entry. External service
fields contain an API URL, model and obscured replacement key. Read responses
contain only `hasApiKey`. A successful save clears the typed secret. Configuration
writes use expected revisions; conflicts and uncertain results require refresh
while retaining the draft. Catalog errors do not replace saved configuration.
Disabled chat retains readable history while blocking new messages.

**Enable thinking for chat** sits below the chat enable switch and defaults off.
It remains editable while chat is disabled and visible for either provider.
The existing save/reset actions and dirty-state handling include this preference;
provider changes and refresh preserve the draft. Missing fields in older API
responses mean off. Supported models may take longer with thinking enabled.

Successful settings saves show a brief accessible SnackBar outside the form.
The unsaved badge, credential status and removal action keep stable space through
the save response, so clearing the draft does not move the controls.

Internal Ollama settings include a requested context length, initially 32,768
tokens, with whole-number validation from 1,024 through 1,048,576 and a separate
Use 32k default action. This value is independent of document AI processing.
Optional Check model limit reads the exact model through the chat administrator
API and shows the advertised maximum and effective capped value. Unavailable
metadata does not block settings saves or invent a limit. Inference verifies the
maximum before requesting the smaller of the saved context and that maximum.
Accepted messages retain the setting captured when they were submitted.

The settings Cubit preserves invalid text through refreshes and fences model
lookups after model/provider changes or disposal. Lookup failures remain separate
from save errors. External mode retains the Ollama choice and explains that the
external service manages context. A temporary invalid Ollama draft is omitted
when saving external settings, preserving the server's existing value.
`AppModelContextField` is a shared dumb presenter also used by AI extraction.

Tests cover generated-client transport, private response errors, uncertain
acceptance, pagination, deletion confirmation and retry, late deletion reads,
selection races, push refresh lifetime, configuration conflicts,
secret clearing, independent navigation claims and draft restoration. Widget
coverage includes 320/390-pixel screens, 200-percent text, dark appearance and
persisted tool progress. The browser scenario configures its independent model,
uploads evidence, completes the real Temporal/tool reply, opens a source and
restores the conversation after replacing the complete app scope.

See the [backend chat architecture](../backend/ai-chat.md),
[shared UI components](components.md), and the
[testing guide](../../development/testing.md).
