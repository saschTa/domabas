# Mobile document scanning

The Android and iOS apps collect camera pages in a local draft and upload one
PDF when the user submits it. Scanning uses the existing `documents:upload`
claim independently of document-read and metadata-create permission. Web, Linux,
macOS and Windows retain their document workspace without initializing mobile camera
plugins. General file selection and drag-and-drop are separate upload work.

## Capture and presentation

The rear camera detects page edges during framing. After capture, the scanner
detects the upright still again and lets the user adjust four corners before
perspective correction. Preview geometry is never reused blindly for a different
still image. The correction view uses a bounded preview; the original pixels stay
behind the camera/data boundary. Users can add pages, move them earlier or later
in the draft and remove a page before submitting.

The live camera uses the available screen body independently of the review form's
width limits. Bounded, scrollable guidance and safe-area actions leave the rest
for a contained camera image and its outline. The live image has no correction
handle inset. Different sensor and screen proportions can leave dark bands;
the full framing area remains visible in portrait and landscape. Correction
retains its whole-image geometry and accessible corner controls.

`ScannerCamera` and `ScanDraftRepository` are the scanner's domain ports.
Immutable domain values describe camera state, captures, geometry, pages and
draft outcomes. `ScannerCubit` owns interactions and operation state. Native
camera, detector, files, image correction and PDF generation remain in scanner
data adapters. App composition supplies a preview builder over the current
camera controller; data does not return widgets and presentation does not import
the camera adapter. No plugin or generated API value enters the domain.
The image presenter privately copies immutable domain byte views for Flutter's
codec boundary and reuses its provider while the bounded image bytes are equal.
Corner, property and theme updates therefore do not repeatedly decode the image.

Only one frame detection runs at a time, with a minimum 100 ms interval. Camera
shutdown drains actual initialization and detection work. A captured correction
image has a separate lease from the camera controller, so backgrounding can
release the camera while preserving correction. Discarding or closing waits for
active work before deleting its input. Generation and orientation checks reject
stale frame results. App composition coordinates camera handoff across sessions.
Capture stops admitting live detection immediately and requests the photograph
before stopping the stream or draining the current detector. Storage admission
still precedes the shutter, with cancellation and ownership checked again after
asynchronous storage work. Camera state distinguishes capturing (hold steady)
from processing (the platform has returned the still file). The live detector
still drains before still detection and camera disposal. These phases do not
measure sensor exposure time or promise a particular device shutter latency.
If a camera negotiates different preview and analysis aspect ratios, live corners
are hidden with capture-and-adjust guidance. The plugin exposes no crop relation
that would make those coordinates reliable. Still detection and correction remain
available, and the preview retains its own dimensions.

Appearance changes preserve scanner state. The covered document collection
pauses automatic reads while retaining realtime invalidation. A confirmed upload
invalidates the collection through an app callback when read permission permits;
realtime messages never overwrite a local scan or repeat an upload.

## Local draft ownership

There is one durable draft per canonical API endpoint, user ID and namespace ID.
The endpoint includes its base path; bearer tokens are not part of the key.
Signing out clears exposed state and cancels new work while preserving committed
files for the same owner. Another account or library cannot restore that draft.
Incomplete property edits can be saved locally and are validated on submission.

An app-owned storage coordinator serializes each owner's lease and admitted work
across authenticated scopes. New sessions wait for previous writes and accepted
upload finalization. A replacement scope cannot receive old UI callbacks, and
old cleanup cannot remove a different draft.

Pages are written before a staged, flushed manifest atomically replaces the
single primary manifest. The previous primary remains authoritative until that
replacement; there is no older-manifest fallback. A corrupt committed manifest
or missing referenced file blocks submission and requires explicit recovery or
discard, preventing an incomplete or previously attempted draft from becoming
an ordinary editable upload. File deletion follows removal of its references.
Committed pages retain their capture identity, so retrying Keep after a local
read or cleanup failure cannot append the same capture twice. Capacity scans,
reservations and reservation releases share one allocation queue.

Page moves use a stable page ID and its final zero-based index. The repository
validates editable state and the destination inside the owner's serialized lease,
then atomically commits the order and revision without changing page assets.
No-op moves leave the revision unchanged. The Cubit coordinates pending property
saves and publishes the persisted order. That order survives restore and controls
PDF output; read-only upload attempts cannot be reordered.

Drafts stay in private application storage. Android keeps its backup exclusions;
iOS excludes the actual scanner root from backup before acknowledging a save.
This uses application storage isolation, not an additional encryption scheme.

## Limits and submission

The scanner accepts at most 20 pages. Input stills are checked against 20 MiB and
20 million pixels before decoding. Corrected JPEGs have a longest edge of 2,000
pixels, at most 3 MiB per page and 18 MiB combined. Thumbnails and correction
previews are bounded separately. The PDF preserves image proportions and page
order, with a physical longest edge at most 842 points and a 20 MiB file ceiling.
Storage admission accounts for durable files, temporary work and pending cleanup;
it never evicts another owner's draft.

The form supports title, description, tags, kind, sender, recipients, CC, BCC,
document date, subject and message ID. The initial title, local date and document
kind are editable. Shared pure upload validation matches backend text, list,
calendar and metadata-byte rules.

The document data source prepares sparse metadata and sends exactly one file and
one metadata part through the authenticated `ApiClient`. This avoids the pinned
generator's extra file-text field and null metadata values without editing
generated code. A scanner-owned data port and app adapter connect this reusable
transport; only data records carry prepared JSON bytes.

Before sending, the draft stores the exact PDF, prepared metadata, hashes and
attempt state. Timeouts, aborted connections, server errors and unreadable
acceptance responses leave a read-only uncertain attempt. Deliberate retry sends
the same bytes; it does not regenerate the PDF. Missing or corrupt cached bytes
block retry. A 409 leaves the draft available for checking and explicit discard.

A validated 202 means accepted for asynchronous processing. Acceptance is
separate from local cleanup: its receipt and tombstone prevent cleanup failure
from offering another upload. Known acceptance still finalizes when the old UI
or session closes. If a crash occurs before that receipt can be persisted, the
previous attempt marker restores as uncertain. Uploads are never retried
automatically.

## Dependencies and evidence

The pinned scanner uses OpenCV on Android and Apple's system Vision framework on
iOS. Its wrapper and Android detector are open source; Vision is an operating
system framework. The Dart `pdf` encoder creates image-only output. Skia's C++
PDF backend would require separate native bindings and binaries and is not the
encoder used here.

Exact package versions are recorded in [pubspec.lock](../../../frontend/pubspec.lock).
The [platform guide](platforms.md) explains native dependencies and permissions.
Native fixture tests can prove detection and correction for their input images;
builds, browser tests and geometry tests do not prove physical camera framing,
permission behavior or live overlay alignment. The [testing guide](../../development/testing.md)
keeps those device checks separate.
