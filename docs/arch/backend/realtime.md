# Realtime invalidation

`GET /api/v1/realtime` upgrades to WebSocket using `domabas.realtime.v1`.
The canonical OpenAPI document defines the handshake, strict frame models and
protocol extension. Generated Go registration remains the only endpoint registry;
the Dart adapter uses generated frame DTOs behind its domain repository.

Browsers send their existing in-memory bearer in one bounded authentication
frame, never in a URL, cookie or subprotocol. The server allows five seconds and
1 KiB for that frame. Exact Origin checks use configured `CORS_ORIGINS` or the
direct request scheme and Host, including effective port. Native clients may omit
Origin. Reverse proxies must preserve Host; TLS termination needs an explicit
external HTTPS origin in configuration. Forwarded headers do not grant trust.

The namespace claim `realtime:connect` enables the entry point. Every ready frame,
outgoing hint batch and heartbeat checks a fresh short read-only repeatable-read
snapshot. The session, active membership and feature claims remain authoritative.
Database errors fail closed. SQL transactions end before socket writes. A change
committed after authorization may race bytes already authorized for delivery;
revocation takes effect on the next check, including the bounded heartbeat check.

Frames contain only protocol version, type and topic names. They never contain
IDs, content, titles, counts or timestamps. Ready/resync include identity and
private activity plus currently allowed feature topics. Clients reread the REST
API for actual data. Own membership changes refresh own activity even after
access to a source library disappears. Other users' mailbox and activity events
are excluded. Document changes also invalidate eligible processing read models
because job titles and deletion status join current document records.

Paperless run and item changes emit a private Paperless topic. It requires the
import, document-read and upload claims in the connected namespace and belongs
only to the run owner. Chat conversations, turns, messages, tool results and
sources emit the private chat topic under chat:use. Bookkeeping leases and checks
remain silent. Reindex changes notify namespace processing readers and system
processing administrators. Up to ten distinct topics fit the existing 512-byte
frame limit.

## Publication and recovery

Migration 012 adds semantic triggers and a transactional PostgreSQL NOTIFY
publisher. Trigger comparisons exclude bookkeeping timestamps, processing leases, heartbeats,
credential rewrapping and other bookkeeping. Session insertion is silent; public
identity changes and own authorization changes have separate signals. Workflow
activities and HTTP mutations use the same publication path. Rollbacks publish
nothing. Existing applied migrations remain unchanged.

One dedicated connection per Go process listens on a channel derived from the
actual PostgreSQL schema. Payloads carry the exact schema and bounded internal
routing attributes. LISTEN commits before the listener becomes healthy; sockets
subscribe before ready. This allows a REST baseline after ready without losing a
change between subscription and baseline. The listener has one I/O owner, probes
with a two-second deadline at least every ten seconds, and reconnects with bounded
backoff. Listener loss makes readiness fail and closes sockets; recovery requires
a fresh connection and authorized baseline.

This is best-effort invalidation, without an event log, cursor or replay. The
shared ingress queue has 256 entries and each socket coalesces at most 64 signals.
Overflow requests a conservative authorized resync. A batch is removed before
its checks/write so new signals remain pending. Job clients refresh on ready and
server resync, with no polling fallback.
Only document and identity views retain periodic recovery reads.

## Resource and process lifetime

The server limits connections to 128, unauthenticated connections to 16 and
connections per authenticated user to four. A process-wide token bucket admits
four upgrades per second with burst sixteen. Initial authentication and ongoing
checks use separate bounded capacity; no client-address map trusts proxy headers.

Only the generated realtime route opts into streaming lifetime. Ordinary routes
retain their ten-second or explicit sixty-second deadlines. Upgrade deadlines
are installed before the HTTP 101 flush; inherited socket deadlines are cleared
only after a successful handshake. A sustained reader handles control frames;
pings and application heartbeats run every twenty seconds. Writes have a
two-second deadline, pong waits ten seconds and connections rotate after thirty
minutes. Slow or malformed clients close rather than accumulating payloads.

The supervisor owns hijacked sockets independently of HTTP Shutdown. Shutdown
starts socket closure before ordinary HTTP draining, forces noncooperative peers
closed after one second, joins socket tasks, and stops the listener before worker,
Temporal and database cleanup. Startup context cancellation does not own the live
listener or sockets. Domain ports, SQL sources, transport and bootstrap retain the
normal [architecture boundaries](boundaries.md).

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
