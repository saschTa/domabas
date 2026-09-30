# Live updates in Flutter

Each authenticated dependency scope owns one realtime repository and abortable
transport. The workspace owns its RealtimeCubit, subscriptions, health indicator
and fallback timer. Logout, account replacement, backgrounding and disposal close
the socket and fence late completions. Returning to the foreground reconnects and
requires ready before treating updates as healthy. A 4401 or 4403 close ends only
the captured authenticated scope.

The data source derives ws/wss from the validated API endpoint while preserving
its path prefix, explicit port and IPv6 host. It uses pinned web_socket_channel
3.0.3 with separate native and browser connection handles. Cancellation physically
aborts pending handshakes; a timed-out Future alone is insufficient. Frames pass a
bounded parser before generated DTO decoding. The parser rejects duplicate keys,
invalid Unicode, unknown fields, duplicate topics and binary frames consistently
on Dart VM and JavaScript targets.

App composition injects the same native HTTP client factory used for API traffic
into WebSocket attempts. On Android this includes system and user-installed CA
certificates; other targets retain their existing trust stores. Aborting while
certificates load closes the late-created client without starting a handshake.
See [Android certificate trust](platforms.md#android-certificate-trust).

Ready, invalidation and resync only mark domain views dirty. REST repositories
remain the source of truth. `AutomaticRefresh` is a small pure-Dart scheduler under
`lib/scheduling`, shared by presentation state owners. Each instance owns one read,
one retained dirty bit and one timer. It coalesces for 250 milliseconds and limits
reads to one per second, or thirty seconds after failures. Hidden views and busy
mutations retain dirty state; a hint arriving during a read schedules one later
read. No uncertain write is retried automatically.

Document processing, reindex, email, Paperless, personal activity, chat and the
workspace Activity indicator refresh from push notifications. They have no
periodic or disconnected polling. Ready and server resync refresh every allowed
job topic after connection or recovery. During an outage, job progress remains at
its last known snapshot; explicit refresh is still available.

Documents and visible identity lists retain their fifteen-second disconnected
fallback and sixty-second safety resync. That periodic resync excludes every job
topic. Connection retries and heartbeat watchdogs manage transport health only.

## View ownership and drafts

Document invalidation resolves the latest desired criteria while retaining the
last successful snapshot, cursor history and layout. The collection Cubit tracks
an invalidation revision and consumes only revisions covered when the current
read was admitted; a later hint remains pending. Direct desired reads can satisfy
queued refresh work without a duplicate request. Debounce, composition, invalid
text, active reads, saves and viewers suspend the scheduler while preserving its
dirty state, rather than polling a busy callback. The collection pauses behind
an open viewer. A route observer
created in app composition marks only the top viewer active; foreground state is
also required. Viewer resources, requests and email-link state close with their
own document scope.

Automatic viewer refresh rereads metadata and extracted text without downloading
the original again. Metadata and OCR drafts remain unchanged. An OCR revision
change marks a conflict while retaining the edit's original base revision;
automatic reads do not acknowledge an uncertain save or clear reconciliation
requirements. Remote deletion releases original/preview resources and disables
writes while keeping drafts visible and selectable for copying.

Email links refresh automatically on the first page. If the user loaded additional
pages, an invalidation preserves the displayed list but marks it stale and disables
open/load-more actions until explicit Reload links. This avoids losing history or
following stale targets without unbounded historical-page revalidation.

Identity refresh uses the existing current-identity REST endpoint. Name/email
updates change display state without replacing AuthSession or resetting document
navigation. Authority or scope changes require sign-in again. Member, invitation,
library and system-user list refreshes retain the loaded range and widget-owned
forms; each page request stays within the existing API limit. Offset pagination
still has its documented cross-request concurrency limits.

Background reads use separate request and presentation state. Documents keep
their status-line geometry, preview resources and pagination controls while an
automatic read is pending; page navigation supersedes that read. Processing
mutations cancel and fence background responses before saving or requesting a
reindex, keeping revision and request-ID checks. Email accounts use the same
existing cancellation boundary. Identity mutations wait for the current background
read, then recheck the current target and authority. Known administrator counts
remain visible during refresh and errors, while failed reads block role changes.
Personal activity and first-page email links refresh without toggling foreground
progress. Errors remain visible until a replacement read succeeds.

The [realtime widget tests](../../../frontend/test/widget/realtime_workspace_independent_test.dart)
cover workspace refresh behavior. The [testing guide](../../development/testing.md)
explains the browser and real-service suites.

See [session ownership](identity.md), [document state](documents.md), and the
[protocol and server lifecycle](../backend/realtime.md).
