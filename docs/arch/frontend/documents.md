# Document workspace and design

The document feature separates its collection, opened-document state, binary
transport and rendering. It uses the real namespace-scoped API and keeps generated
models in data adapters. The original PDF, PNG or JPEG is the visual source;
correcting OCR does not rewrite that original.

## Collection and visual language

The collection uses pages of 48 records in the backend's stable newest-first
order. Grid and list modes show the same title, a single row of up to three
ordered tags with an overflow count, and processing state. Full tags remain in
tooltips, semantics and document details. Preview failures leave details and permitted actions usable.
Metadata-only records have an explicit no-original state.

Grid cards reserve the same preview, two-line title, tag and footer areas for
every record. Search cards also reserve two snippet lines even when the snippet
is empty. Text slots use measured theme typography and the active text scaler;
neither missing originals nor long tags change a card's height. The grid fills
the available workspace width with at least 240 logical pixels per card, adding
columns on wide screens. Columns account for the inter-card gap. Pages stay
bounded and lazy rows build only visible cards. Lists use a 56-by-72 preview,
12-pixel padding and 8-pixel row gaps, with inline metadata on wide screens and
stacked metadata when needed.

Users with both document-read and document-search claims can apply a combined search
term, document kinds, AND tags, literal sender/recipient filters, and six stable sort orders.
Type chips expose Documents, Letters and Emails directly below search and inside
the filter dialog. Multiple types combine with OR; All types clears the type
restriction. Selecting Documents and Letters excludes email records while
retaining attachments with those kinds. Type changes apply immediately, reset
pagination and retain the latest term and other filters. Active summaries can
remove individual filter categories, and Reset filters preserves term and sort.
The dialog groups Document type separately from the Tags and people lookup.
Typing applies the latest valid term after 300 milliseconds; Enter or Search
submits immediately. Active IME composition and invalid text never submit. The
search field releases focus on outside touch, collection drag and completed
submission, so returning from another action cannot reopen its keyboard or reveal
the offscreen search field. Background refresh preserves active editing and the
collection scroll position.

The collection Cubit owns the raw term, composition, desired filters, debounce and
intent revision. A meaningful edit cancels and fences the previous read before
waiting for the timer. Sort, filters, refresh and mutation reconciliation all use
the latest desired term. Clear search returns to ordinary offset browsing and
preserves its layout. The adapter requests `hybrid` mode: typo-tolerant and semantic
matches appear together, with title/property matches before document text.
Empty filter-only searches do not need inference. The backend's existing
fulltext and semantic modes remain available to API clients.

Nonempty hybrid search omits an exact total because semantic relevance uses
approximate indexed retrieval. The collection footer says “Search results” and
keeps Next, Previous, First and background refresh driven by cursors. Full-text,
empty searches and browsing can still show exact counts. A missing total never
becomes a displayed zero. Search validation failures have a search-specific
message instead of the document-save error. Server-side search failures say that
the server could not complete the search; only transport failures and client
timeouts use the connection failure message.
Search requests allow 35 seconds, leaving time for the backend's 30-second
request budget and response delivery. Editing the query still cancels the
previous request immediately.

Browse and search use one card presenter and retain the same grid/list selection.
Search adds a bounded plain-text snippet beneath the title. The entire card has an
accessible Open document action. Its optional original descriptor supplies only
SHA-256, media type and size; painting results never hydrates metadata or OCR.
Eligible PDF/image originals enter the existing bounded preview coordinator only
with download authority. An absent search descriptor means Preview unavailable;
email retains its email placeholder. Only a complete browse record can establish
No original file. The lazy collection scroll contains its cards followed by the
count and pagination inside a transparent full-height pane. A compact progress slot
above the cards stays the same height during refresh. Loading and error messages
appear in a bounded, scrollable row below the collection and above phone navigation;
healthy collections reserve no empty status row. Its separate persistent toolbar has bounded scrolling for short
windows and enlarged text.

Search uses the available toolbar width beside Filters, Sort and Grid/List.
Compact layouts keep search and the library picker above the controls.
The field controller and focus node survive responsive changes. Search and clear
actions are embedded in the field with 48-pixel targets. Type shortcuts and selected
filters use a horizontally scrollable strip; healthy state needs no extra status
row. Pending work, errors and stale results show readable status text.
Filters select existing tags, senders and recipients from a namespace-scoped
vocabulary. The authenticated composition injects a narrow vocabulary repository;
a route-scoped Cubit owns one active field and abortable lookup. Tags keep AND
semantics, while selected addresses use independent exact match modes. Legacy
contains filters remain explicit until changed. Selected server keys and original
values survive route dismissal and case-only representative changes. Metadata
editing and scanner properties still allow new values.

Filter changes apply immediately. Done, Back and barrier dismissal retain them.
Every callback validates the exact route, navigator, generation and owning scope;
covered or replaced routes cannot change filters. One coordinated scroll body
contains controls, wrapping selected values and a lazy options list; the Close
control stays outside it. Rows use two natural-scale lines, full semantics and
tooltips. Accessible summary actions expose an activation action.

Lookups request 40 records at a time and retain at most 400 options plus at most
22 selected records. The client deduplicates by opaque server key and retains no
unbounded seen set. Continued forward scrolling releases only whole page segments
above the current visible row. A narrow scroll position corrects the stable key
and intra-row anchor during layout, using the current scaled row extent and
measured header geometry before paint. A backscroll that makes release unsafe
discards the bounded response and keeps the cursor; Retry or leaving and returning
to the end threshold can admit it later. Failures require explicit Retry.
Restart list reopens the current query from its first page and keeps selections.
The window limit does not cap the searchable corpus.

Search pages use opaque cursors with an absolute page ordinal and at most 50
previous positions. The committed snapshot, count, page and history stay unchanged until a current
request succeeds. Desired controls remain separate from that snapshot. Retry owns
an exact failed intent and cannot restore an older query after another edit.
Refresh resolves the latest desired target and coalesces an identical active read.
An empty later page recovers to the first page once. These are live results;
metadata/OCR edits between requests can change ordering and membership.

The visual language follows the shared Studio neutral light and dark palettes.
Rounded document cards sit directly on the canvas without borders, shadows or
hover translation.
The feature-owned toolbar contains search, filters, sorting and view selection.
Pulling down from the top refreshes the collection, including an empty library,
while preserving search criteria and the current page. The refresh indicator
waits for the read to finish; failed reads keep the last snapshot and a Retry
action. App composition places the toolbar in the persistent top bar beside the library
picker; standalone screens use the same controls above their collection. The
selected navigation identifies Documents; counts scroll with the pagination while
the surrounding pane stays fixed. Opening a card or row
goes directly to the original full-size document viewer.
An opaque metadata pill fades over the preview to show original type, size and
date without fetching additional data. Hover uses a subtle surface fill.
Keyboard focus uses a primary container fill and retains supplemental details;
list rows expose those details through a tooltip. Preview arrival has a brief
reveal. Actions also work by touch, with complete information in the opened
document. Reduced-motion settings suppress translation and optional transitions.
Controls wrap for narrow windows and enlarged text instead of relying on desktop
platform checks. The [shared component guide](components.md) defines the theme,
navigation breakpoints and presenter boundary.

## Open document and editing

Opening a record uses an inset, rounded dialog route on the existing Navigator.
Wide windows initially show details beside the document. Compact windows open
details in a separate rounded dialog with the same save/discard protection.
The viewer provides back, document information, fit/zoom and page controls.
A circular, icon-only download action saves the original through the existing
download claim. It reuses loaded bytes, fetches email originals on demand and
keeps save failures visible with retry. App composition injects a file-saving
port; the data adapter supplies the original filename and MIME type to the
platform save dialog or browser download. Metadata-only records have no download
action, and closing the viewer prevents a pending read from starting a save.
PDFs scroll through their pages; images support pan and zoom. Rounded controls
overlay the complete canvas, with no footer strip. They wrap and scroll when
space is limited. PDF initialization and Fit account for the measured controls
height so the complete page remains visible above them. Properties and extracted
text remain available when a file cannot render, subject to the user's claims.
PDF text selection keeps its touch handles and copy menu, with the additional
selection magnifier disabled. Its context menu uses Flutter's adaptive toolbar
and localizations so the renderer's separate Material/Cupertino UI dependency
does not create a second localization requirement.

PDF search uses PDFium's native text layer and highlights matching page text.
Extracted-text search operates separately on OCR text. Scanned PDFs can have no
native matches; the UI does not claim that OCR matches have page geometry that
the backend never stored. A correction changes searchable extracted content while
the original page stays unchanged.

Properties include title, description, ordered tags, kind, sender, recipients,
CC, BCC, document date, subject and message ID. File identity and processing
information remain read-only. Forms validate domain limits, preserve drafts on
failure and require explicit save/cancel. OCR saves carry the observed revision;
a conflict requires reviewing the newer value. Uncertain writes are reconciled
through a read before retry. Delete has a separate confirmation and returns to a
refreshed collection, including when the last item on a page is removed.

Visibility derives from session capabilities for metadata, originals, OCR,
processing retries and deletion. The server enforces the same scoped claims.
Read-only access does not expose write actions, and missing download authority
does not trigger a hidden original fetch.

## State and resources

`DocumentsCubit` owns page, mode, loading and collection state. Route-scoped
`DocumentCubit` owns opened metadata, OCR revisions and mutations. Immutable
presentation states stay separate from transport objects. Renderer/search/focus
controllers are disposable interaction objects; rendering code remains inside
presentation and receives bytes through the domain repository.

Desired criteria, selected vocabulary records, the committed snapshot, summary
results and cursor history belong to `DocumentsCubit`. A nullable snapshot flag
distinguishes an uncompleted initial read from a successful empty collection.
Each collection operation has its own cancellation future, generation and intent
revision; replacement cancels only that operation, leaving viewer I/O alive.
Session shutdown still cancels the whole datasource scope. Term, focus and scroll
controllers remain mounted behind an open viewer, so returning without edits
preserves the current page, desired term and scroll position.

Metadata hydration is separate from mutation notification. Confirmed writes,
processing retries, deletion and successful uncertain-write reconciliation refresh
the criteria current at notification time. Search refreshes from page one and
does not insert or patch summaries optimistically. A failed refresh cannot retry
a confirmed write. Deletion starts invalidation before the viewer can dispose.
Search transport uses a sparse serializer around the generated DTO to omit null
optionals. Legacy external criteria keep their normalization path, while canonical vocabulary
tags are copied without another fold. Go-compatible trimming preserves U+FEFF and
raw scalar validation rejects malformed UTF-16 before normalization. Exact address
selections send their original display value, never a folded value or opaque key.
The backend validates all criteria and owns Unicode comparison.

Card metadata reveals use a local opacity animation without moving the card.
Both disable-animations and platform reduce-motion changes settle active tweens;
the collection and cards observe platform accessibility changes explicitly.
Reduced-motion collection loading uses static text.

Returning from a viewer keeps ready preview images and their completed reveal.
Preview requests use an immutable document ID and thumbnail descriptor, independent
of complete metadata. Identity includes the source hash, renderer revision and
output hash, so browse, search and layout changes share ready thumbnails, while
background generation replaces an empty preview. The adapter validates every
present thumbnail and original descriptor before generated DTO parsing.
Incomplete or malformed descriptors fail the page instead of becoming a download
request. Missing thumbnails show a placeholder and never fetch an original.
Both `documents:thumbnails:read` and `documents:download` are required for previews.
A separate resume revision
retries empty previews interrupted by pause, including cancellation that has not
yet settled; genuine failures still require Retry. Collection admission resumes
only in the foreground with collection ownership and all viewers closed. Cancelled
physical work remains counted until it drains, and unadopted image clones are
disposed even when cancellation races a completed result.

Preview admission covers thumbnail download and JPEG decoding together, with two
active jobs and an 8 MiB thumbnail cache. The server fits previews within 256 by
360 pixels and 256 KiB. A streaming response cap applies before generated client
buffering, and MIME, dimensions, byte count and output hash must match the
descriptor. Cards neither download originals nor open PDF renderer instances.
An allocation-free marker preflight validates the server's single-scan baseline
JPEG and bounded dimensions before any image decoder runs. Metadata that could
change orientation and additional frames are rejected; the server strips them.
The [thumbnail pipeline](../backend/document-thumbnails.md) generates missing
artifacts autonomously and emits the normal document invalidation when ready.

The full viewer owns one original and limits its raster cache to 64 MiB.
PDF and image renderer boundaries
use bounded typed-byte copies so debug JavaScript interop receives native typed
arrays instead of immutable Dart list views. The PDF copy is held by a stable
document reference, avoiding reference replacement during asynchronous initialization.
The image copy is scoped to decoding and its codec is then disposed. Each bridge
copy is at most the 100 MiB original limit. Image headers must declare no
more than 50 million source pixels before decoding, matching the processor limit.
The retained image is resized to a longest edge of 4096 pixels. Flutter web first
decodes original pixels before resizing, so this target does not bound transient
decoder allocations. Cache limits likewise do not bound every PDFium or browser
engine allocation.

The authenticated HTTP wrapper rejects original responses exceeding 100 MiB before
the generated client's buffering step, with a separate 256 KiB thumbnail bound.
Original requests have 120-second deadlines
and explicit cancellation. Closing a consumer or replacing its scope cancels I/O;
late results cannot enter a replacement session or namespace. Logout cancels
document work while retaining identity transport just long enough to revoke the
session. Caches and rendering handles belong to their scope, never a global
service locator.

## Processing jobs and reindexing

`DocumentProcessingRepository` is a separate document-domain consumer port. Its remote
adapter maps generated API values to immutable pipeline snapshots, jobs and
reindex batches. `ProcessingCubit` owns the namespace jobs page;
`ProcessingSettingsCubit` owns installation settings and aggregate batch history.
Neither imports generated transport types or Temporal SDK concepts.

Thumbnail generation joins the same chronological history and full-history
filter counts. Its pipeline overview and attempt details use the shared
responsive diagram: Original, Render thumbnail, Thumbnail ready. The render
step includes saving the preview; there is no separately recorded publishing
step. Details show only retained stage evidence, timestamps and renderer revision,
without OCR or AI configuration. Older terminal attempts without render evidence
say Not recorded. Returning from details preserves the selected pipeline/status
filters. The activity panel uses the thumbnail label and image icon as well.

The Jobs destination requires either `documents:jobs:read` or
`documents:reindex`. Job history requires the first claim and the explicit reindex
action requires the second. A live title and Open document action require
document-read authority as well. Deleted documents retain their job outcome and
an ID label. The Admin navigation group includes every individually authorized
leaf: processing administration uses `system:document-processing:manage` without
requiring system user administration. That system claim grants aggregate progress
and the dashboard link, not namespace document details.

The namespace and administrator screens show separate ingestion and AI diagrams.
Ingestion shows the original, OCR/effective text, embeddings and Searchable.
AI processing follows publication, with independent invoice and property steps.
Embedded invoice XML is labeled structured extraction when invoice AI is disabled;
it remains automatic and uses no model. Both diagrams switch to a vertical flow
on narrow screens and enlarged text. OCR correction attempts identify that
extraction is not repeated. Reindex confirmation states that originals and saved
OCR corrections are preserved, and records without originals are skipped.
Batch totals remain explicitly incomplete during enumeration; outcomes count
completed ingestion work, not merely dispatches or optional AI work. Historical
combined jobs retain their recorded pipeline version and original graph.

Document properties show Searchable independently of AI status and failure.
An absent AI summary means no separate attempt was recorded, while a recorded
skipped attempt is shown as Skipped. AI retry requires `documents:retry`, creates
a secure request UUID before transmission and retains that UUID and configuration
revision after an uncertain response. Retrying the same request cannot schedule
duplicate work or rerun ingestion. The viewer fences completions after close.

Unified Jobs includes separate ingestion and AI filters. Pipeline and status
criteria reach the server before pagination; changing either cancels old reads
and resets its cursor. Active AI jobs remain in the activity indicator after
ingestion succeeds, and personal activity identifies AI attempts independently.

Property extraction settings live under Admin settings → Document processing.
The existing system processing claim governs the instance-wide form and graph
edit action. Internal Ollama defaults to `qwen3.5:4b` with extraction off; its model
downloads when a durable job first needs it. External mode accepts an
OpenAI-compatible API base URL, model and optional replacement key. The client
receives only whether a credential is stored. A blank key preserves it at the
same destination; an explicit removal or changed destination removes it unless
replaced. Submitted keys clear after confirmed saves. OCR and extraction changes
save together with the observed revision. AI-only changes schedule AI processing
without removing searchable state; OCR changes schedule ingestion reindexing.
Disabling an AI step preserves existing extracted results.

Each extraction step has its own **Enable thinking** switch directly below its
enable control. Thinking defaults off and remains editable while the step is
disabled. Both providers show the switches; provider changes and background
refresh preserve drafts. Save settings persists each choice independently, and
Use saved settings restores them. Older API responses without the fields mean
off. The same controls appear in the pipeline dialog. Supported models may take
longer when thinking is enabled; the shared LM Studio JSON preference is separate.

External service shows **LM Studio compatibility mode** directly below API base
URL in the shared model connection. It defaults off and applies to both property
and invoice extraction. The native switch uses the existing explicit Save settings
and Use saved settings actions; changing it marks the form as unsaved. Drafts
survive background refresh and temporary provider changes. The switch is hidden
for Ollama, which ignores its retained preference. Older API responses without
the field are read as off. The same form is used in the pipeline edit dialog.

Internal Ollama has a requested context field shared by property and invoice
extraction, independent of AI chat. It defaults to 32,768 tokens and accepts whole
numbers from 1,024 through 1,048,576. Use 32k default updates the draft, while Use
saved settings restores the saved form. Optional Check model limit uses the
document administrator endpoint, so no chat claim is required. It displays the
model maximum and the smaller effective context without reducing the requested
setting. Inference verifies this limit for each accepted pipeline snapshot.
Unknown metadata leaves the effective value unknown and does not block saving.

The shared `AppModelContextField` presenter receives values and callbacks from
the feature. Its Cubit preserves invalid numeric drafts across refreshes,
cancels obsolete lookups, and separates discovery errors from save errors.
External mode retains the Ollama setting and explains that the provider manages
context. An invalid temporary Ollama draft is omitted on an external save so the
server retains its existing value.

`LLMConfiguration` is an immutable safe read model; `LLMSettingsDraft` contains
temporary write values and validation. The settings Cubit preserves drafts and
focus during background reads. Uncertain writes require a fresh read, and the
client does not claim to verify an opaque API key. The shared form appears inline
and in a scrollable dialog opened from the settings graph. Namespace and historical
snapshots expose only extraction enabled/model values. The job graph labels an
enabled historical stage Configured, because a no-text document may skip it;
In progress and Stopped here reflect the recorded `enriching` stage. Older
snapshots without extraction configuration say Not recorded.

Successful OCR and AI settings saves show a brief accessible SnackBar outside the
page's scrollable form. The extraction dialog keeps its own success badge in the
fixed actions area and suppresses the page SnackBar. Unsaved badges and credential
controls retain their layout across saves, including wrapped narrow layouts.

Only the visible foreground processing leaf refreshes on realtime notifications,
with no overlapping reads or polling fallback. Leaving the page, opening
a document, backgrounding the app or replacing the session cancels that consumer's
requests. Scope shutdown cancels all processing transport. Epoch and request
guards reject late results. Loading another history page preserves the other
list's extent. While browsing older pages, a notification replaces known rows
in place and refreshes every loaded active older row; selected job detail always
refreshes. Pulling down at the top refreshes the page, and a visible notice
explains that this returns to the newest records.

Every reindex request receives a secure UUID before transmission. An uncertain
response retains that UUID and its observed configuration revision for a safe
retry. Settings saves retain their editing revision; a timeout requires reading
the saved configuration before another save. The optional legacy revision field
uses sparse serialization so omission never becomes JSON null. Transport
distinguishes caller cancellation from timeout, including when timeout aborts
the underlying HTTP request first.

The dashboard URL comes from the authorized system API. The client validates an
HTTP(S) URL with a hostname, valid port and no credentials, query or fragment.
The click calls the injected launcher immediately to preserve the browser's
user gesture. `url_launcher` is pinned directly to 6.3.2, the version already in
the lockfile; Android, iOS, web, Linux, macOS and Windows remain enabled. Deployment
configuration and dashboard access controls belong to the backend/operator guide.

The [background job guide](../backend/background-jobs.md) explains durable
acceptance, progress and history rules shared by these screens. See the
[testing guide](../../development/testing.md) for pipeline verification.

## Renderer and deployment decision

The app pins pdfrx 2.6.1. PDFium interprets and rasterizes PDFs; Flutter displays
pages and decodes PNG/JPEG. Skia's PDF backend creates PDF output and is not a PDF
reader. Its name is therefore not used to describe this viewer's parsing engine.

The checked package supplies same-origin Wasm and worker assets. Web builds include
Flutter's own rendering resources locally as well. Document rendering needs no
runtime public CDN. Native targets use the package's fixed PDFium builds; the
[platform guide](platforms.md) records host dependencies and download caveats.
The app includes matching engine/dependency notices in its license registry.

For renderer dependencies and platform handling, see
[platforms and transport](platforms.md#document-rendering). The backend's
[ingestion guide](../backend/document-ingestion.md) describes canonical OCR,
generation fences, search consistency and eventual file deletion.

## Original uploads

Mobile apps also accept PDFs and images from other apps. See
[mobile sharing](mobile-sharing.md) for the native entry points, confirmation,
supported formats and session ownership.

The workspace exposes Upload files under `documents:upload`, independently of
read or metadata-create permission. Create metadata keeps the existing fileless
record flow. Selection accepts originals from all five target platforms; an
external file drop anywhere over the visible web/Linux/Windows application
starts upload automatically. The passive drop invitation renders above the
Navigator without opening a route, changing focus or replacing unsaved forms.
Uploads share the workspace Activity indicator and panel with background jobs
and reindex requests. View uploads opens that same panel, including the latest
40 completed outcomes, pending work and clear-finished action. Transfers show
their recorded phase without inventing byte percentages. Acceptance means the
original reached the server; document processing continues independently.

`DocumentUploadsCubit` owns per-session admission, a 20-entry pending queue,
immutable status rows and delayed collection invalidation. Domain ports contain
opaque candidate IDs and document results, never paths, plugin handles or bytes.
The data acquisition registry owns lazy native paths/browser File handles. One
app-owned coordinator holds the physical content, chooser and portal leases across
session replacement. Busy session operations cancel the admission generation;
late results cannot target a new library. Visible inactive desktop/web windows
still accept external drags. Hidden windows pause queue admission; a mobile
chooser keeps its original scope and may return a bounded batch for resume.
An already-authorized Linux portal transfer also keeps its captured registration
while hidden and admits its bounded completed batch for visible resumption. New
hidden drops/lookups remain blocked. Session busy or replacement invalidates that
registration permanently.

Only one original is read and uploaded at a time. Each read uses at most 64 KiB
steps into one admitted buffer, with a 100 MiB ceiling. Native code rejects leaf
symlinks, directories and special files, opens a regular absolute path, checks
length before allocation, probes after the expected end and rechecks the same
handle. These portable checks do not make stat/open atomic or detect every
same-length concurrent rewrite. SHA-256 describes the bytes actually sent.
Browser FileReader slices are abortable. Logical timeout/cancellation can report
failure while the physical operation and cleanup retain their lease until drain.

The scanner-compatible multipart source sends exactly one file and one sparse
metadata part. General uploads normalize the basename and title, sniff only the
server's supported PDF/image prefixes and leave EML validation to the server.
A strict raw receipt validator checks required wire types, limits and exact sent
filename, title, size and SHA-256 before generated decoding. Valid 202 acceptance
is recorded even after logical cancellation; accepted means processing continues.
Duplicates and definite rejections remain distinct from uncertain responses.
General uploads never retry automatically and retain no original bytes in history.
Only a surviving read-authorized scope invalidates its existing document Cubit.

## PDF password recovery

Password-protected PDFs show an exclamation mark and Password required in the
collection. Opening one shows a masked password form when the session has
`documents:unlock`; read-only users see an explanation. The form preserves
password spaces, reports incorrect passwords inline, and prevents concurrent
submissions. Success clears the password, invalidates cached encrypted bytes and
refreshes the document so the persisted unlocked PDF renders immediately.
Ingestion resumes through the backend outbox. Remote hash changes also invalidate
opened originals. Uncertain responses are reconciled by reading current state
before another submission.

## Invoice classification status

Current AI processing and job history show the invoice decision independently of
the job status. Negative decisions say that extraction was skipped. Uncertain
results explain missing text, incomplete coverage, mixed documents or a conflict
with a prior invoice when available. A succeeded AI job with an uncertain decision
still offers the existing authorized AI retry action. Retry creates a new attempt;
it does not rerun OCR. Missing classification on retained or structured-only jobs
is not presented as a negative result.
