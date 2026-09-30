# Email accounts and personal activity

Email account settings use immutable domain values, a session-scoped repository,
generated API data adapters and separate provider/editor Cubits. Widgets own
temporary controllers and focus. The app composition root supplies concrete
dependencies and cancels their requests when the authenticated scope ends.

## Provider editing

The Email accounts destination appears under User settings when the current
library grants `email:manage`. Each configuration imports into that library and
belongs to the signed-in user. The editor exposes the TLS IMAP endpoint, port,
username, write-only password, mailbox, interval, age and page size. Password
controllers start empty; an omitted replacement preserves the saved password.
Sparse serializers omit absent secrets instead of sending null.

Connection testing is separate from saving and importing. Changing a tested value
invalidates an earlier result. Definite failures preserve the draft; uncertain
mutations require readback. A password write is never automatically replayed,
because nonsecret readback cannot prove which password was saved. Import-now
requests keep the same request UUID while their outcome remains uncertain.

Enabled imports continue after logout. The UI explains that accepted documents
remain in the library after disabling or deleting the provider. A password change
requires a separate Renew background access action; saving an unrelated field
does not grant new consent. The backend initializes credential encryption on first
startup, so a default installation can add email accounts without server key setup.
The capability response still controls credential actions for compatibility with
servers that report email encryption unavailable.

New accounts default to automatic import when the user can read and upload
documents. Editing preserves a saved disabled state. Connection progress, errors
and results appear below the editor actions, and new feedback scrolls into view.

## Unified jobs and pipeline details

Email retrieval joins document ingestion in the single Jobs & pipeline list.
Pipeline filters select all jobs, document ingestion or email import. The email
overview and per-run details use the same shared boxes and connectors as document
processing, following the [unified pipeline UI rules](components.md#unified-pipelines-and-jobs).
The detail page shows timing, email/attachment counts and the last recorded stage.
Importing covers both original and attachment acceptance; counters identify item
failures without inventing a finer execution trace. Downstream ingestion is shown
as separate jobs. Private history remains readable after provider deletion.

The email jobs Cubit uses the owner-scoped, paginated `/api/v1/email-runs` endpoint.
It refreshes the selected job, cancels hidden-screen reads, handles realtime
invalidation and preserves older history during automatic refresh. App composition
merges authorized histories in creation-time/ID order without crossing an unread
page boundary in either source.

Job filter pills show exact server totals across the complete authorized history.
Pipeline totals apply the selected status; status totals apply the selected
pipeline. Each source returns a bounded summary with its normal list page,
independently of the page cursor and selected facets. Cubits retain immutable
summaries while refreshing older pages and discard responses from obsolete
filters or sessions. Missing summaries show an unknown marker; failed refreshes
retain marked prior totals. Email and Paperless totals remain owner scoped, and
successful Paperless runs with failed outcomes count as partially completed.

## Activity and lifetime

Your activity is a topbar action across the authenticated workspace. The feed
spans authorized libraries and labels each row with its library. It separates
active work from finished jobs, with independent previous/next controls and explicit state and
kind. A mail retrieval success means files were accepted, while their parsing,
OCR and embedding jobs may still be queued or running.

The Cubit refreshes on realtime notifications while the workspace is foregrounded,
with one request at a time, cancellation and stale-result guards. Failures retain
prior evidence with its update time. Provider views refresh only while visible.
Neither uses polling or a disconnected fallback. The active badge reports
the current bounded active page and indicates when more records are available.
Activity requests contain independent active and finished cursors. Automatic
refresh rereads the current pages; explicit refresh returns to the newest pages.
Failed navigation preserves the old page and its continuation.

Same-library rows open only currently permitted destinations. A row in another
library offers Switch library; it does not reuse the old context to open a route
after session replacement. Dialog ownership remains exact, so a stale completion
cannot close a newer modal. Narrow windows and enlarged text use scrolling content,
wrapped labels and accessible controls.

## Email document viewing

Email cards use an email preview and do not download originals into image or PDF
decoders. The full viewer displays permitted metadata and safe selectable extracted
text, plus paginated attachment and parent links. Text-read authority works without
original-download authority. A user lacking text-read permission sees only the
permitted metadata. Raw original access retains its separate download claim.

HTML is never rendered or executed, and remote email images are never requested.
Email extraction is labelled parsing or extracted text; the UI does not describe
it as Tesseract OCR. Existing text editing and generation conflict behavior remain
available through the document feature.

See [backend email ingestion](../backend/email-ingestion.md) for the protocol and
authority rules, and the [testing guide](../../development/testing.md) for validation.
