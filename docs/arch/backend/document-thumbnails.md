# Document thumbnails

Collection previews use persisted JPEG thumbnails. Opening a document or choosing
Download original still uses its retained original. Thumbnail generation is
independent of OCR, embeddings, invoice extraction and document AI.

## Discovery and durable work

An installation-wide SQL scan record makes an overdue scan eligible at startup
and admits a new scan at most once every minute. Each scan accepts at most 100
ready PDF, PNG or JPEG documents lacking a thumbnail for their current source
hash and renderer revision. Metadata-only records and email bodies keep their
ordinary placeholders; image and PDF email attachments qualify as documents.

Discovery uses a persisted keyset cursor and a fixed upper bound for each sweep.
Successful thumbnails leaving the missing set cannot cause offset skips. Finishing
a sweep resets its cursor so new records and newly eligible originals behind it
are found. Scan progress and per-document work commit together. The scan holds
no locks while contacting Temporal or the processor.

Finite Temporal workflows perform accepted generation. The shared resource
scheduler admits each render using one worker permit and no model permit. The
100-document page is a discovery bound, not a rendering concurrency setting.
Each two-second delivery poll repeatedly claims and starts accepted jobs until
the scheduler grants no further work. Each claim checks the shared workload
limits and older feasible waiters, then delivery starts the job before claiming
another. A poll is bounded by the maximum configurable workload limit of 256
claims and its existing twelve-second deadline. Rendering can run concurrently;
starting the next job does not wait for an earlier render to finish.
Duplicate delivery and ambiguous starts reconcile the exact retained workflow
identity. Scheduler ownership remains until execution closure is verified,
including when the document is deleted or its original changes.

Malformed, encrypted, unsupported and resource-limited inputs receive terminal
outcomes for that source and renderer revision. Temporary failures retry with
bounded execution attempts and durable cooldown, allowing recovery after an
extended processor outage. One failed document cannot hold the discovery cursor
or hide later records.

## Rendering and storage

The private document processor reuses its existing child-process isolation,
PDFium/Wazero engine, bounded decoder admission and cancellation. It renders only
the first PDF page directly to thumbnail dimensions; this path performs neither
OCR nor model requests. PNG and JPEG input dimensions are checked before decode.
JPEG orientation is applied, and transparent images receive a white background.

Output fits within 256 by 360 pixels without upscaling and is at most 256 KiB.
The service validates encoded JPEG dimensions and identity before accepting it.
The existing 100 MiB original and 50-million-pixel source limits still apply;
small output dimensions do not make arbitrary source decoding inexpensive.

PostgreSQL stores bounded JPEG bytes in a dedicated artifact row alongside typed
source hash, renderer revision, output hash, dimensions, MIME type and byte count.
Ordinary list and search reads select metadata only. Artifact publication and the
successful outcome are atomic. Deleting a document cascades its artifact but
retains execution ownership until closure. Publication and reads require a
matching current source hash, so a stale activity cannot restore deleted content
or attach a preview from an encrypted original to its unlocked replacement.
OCR edits and reindex generations do not invalidate unchanged source bytes.

## API, authority and clients

Thumbnail attempts also participate in the namespace document-jobs feed, its
full-history totals and job details under the existing `documents:jobs:read`
claim. Title disclosure additionally requires `documents:read`. The shared typed
history view normalizes obsolete attempts to Superseded and keeps namespace,
document, status and pipeline filters bound to the chronological cursor.
Thumbnail attempts expose their renderer revision and attempt number while
omitting unrelated ingestion configuration, generation and text source.

New attempts record real status-change, render-start and finish timestamps.
Older history retains unknown start and finish times rather than substituting
scheduler admission or closure. Rendering includes artifact publication in the
same activity; details do not claim an independently observed publishing stage.
Job changes publish scoped job invalidations. Current-attempt identity follows
the retained original hash, current renderer revision and latest render attempt,
independently of OCR reindex generations. Deleted-source history remains visible
without its title or a current-attempt marker.

The canonical OpenAPI contract defines the authenticated thumbnail GET and a
nullable descriptor on document and search results. The namespace claim
`documents:thumbnails:read` is included in normal role bundles and follows the
owner catalog rule. Binary reads also require `documents:download`, preserving
the previous collection-preview content authority. System administration alone
does not grant another namespace's content.

Unavailable and foreign artifacts use the same not-found response. Binary
responses are private and not stored by shared caches. The client verifies the
output identity against its descriptor before caching. Source/result bytes and
user credentials never appear in Temporal history.

The collection downloads thumbnails with a 256 KiB streaming response cap,
bounded request lifetime and cancellation. It retains the existing two-request
admission and 8 MiB decoded image cache. Missing descriptors show placeholders
and never trigger original downloads. Both widget and cache identity include
thumbnail readiness and output identity. Publication emits a document
invalidation so an existing card can load its newly generated thumbnail without
discarding collection pagination. Full document viewing remains separate.

See the [background job rules](background-jobs.md),
[resource scheduler](resource-scheduler.md),
[document workspace](../frontend/documents.md), and
[shared Jobs UI](../frontend/components.md#unified-pipelines-and-jobs)
for the user-facing history and pipeline presentation.
