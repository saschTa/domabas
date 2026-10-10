# Mobile document scanning

The Android and iOS apps collect camera pages in a local draft and upload one
PDF when the user submits it. Scanning uses the existing `documents:upload`
claim independently of document-read and metadata-create permission. Web, Linux,
macOS and Windows retain their document workspace without initializing mobile camera
plugins. General file selection and drag-and-drop are separate upload work.

On phone layouts, Scanner is a primary bottom-bar action for users with upload
permission and a native scanner capability. It opens the scanner over the current
workspace and returns to that same destination when closed. The Documents header
also retains its Scan document action; unsupported platforms explain native app
availability there.

## Capture and presentation

Android opens Google's ML Kit Document Scanner in full mode for each Add page
action. Google Play services owns capture, automatic page detection, crop controls
and image cleanup. The app requests one JPEG, with gallery import disabled, and
saves the returned page directly into its existing draft. Users can add up to
20 pages through repeated Add page actions, reorder them and upload one PDF.
Returned JPEG bytes are preserved without another perspective correction or lossy
encode. If local saving fails, the processed page remains available for Keep page
or Retake page; it has no second set of corner controls.

The scanner SDK manages camera selection. Its public options do not expose a
camera ID or lens choice, and do not guarantee automatic switching between
physical lenses. Domabas therefore has no persisted lens preference for this
scanner. Google Play services and supported hardware are required; the first
scan can require an internet connection to download the scanner. The Android
manifest declares the `document_ui` dependency so Play services can prepare it.
Startup failures check the actual Play services status before suggesting
installation, updates or enablement. Other failures retain a bounded error
reference with the startup stage and SDK status codes; native startup exceptions
are available in Android logs under `DomabasScanner`. Failure leaves
the draft intact and explains how to retry. It does not open the custom camera
as a fallback. See the [Google integration guide](https://developers.google.com/ml-kit/vision/doc-scanner/android)
and [supported options](https://developers.google.com/android/reference/com/google/mlkit/vision/documentscanner/GmsDocumentScannerOptions.Builder).
Images are processed on-device; Google receives SDK usage and performance
metrics. The draft screen discloses this before scanning. See
[data and privacy](../../development/privacy.md#what-other-services-receive).

Pending document properties are saved before opening Google's scanner; a save
failure keeps the user in the draft. Launching the scanner temporarily backgrounds Flutter. That handoff retains
the in-flight scan; cancelling Google's UI returns to the draft without an error.
Closing the owning scope or signing out cancels its native request. Unique request
identities reject late callbacks, and camera handoff waits for outstanding work.
Native result reads run off the Android UI thread and are bounded to 18 MiB before
crossing the platform channel. The data adapter validates JPEG dimensions before
decoding and retains existing draft storage reservations and ownership.

On iOS, Apple's VisionKit document camera owns capture, edge detection, crop and
review. Google ML Kit Document Scanner is Android-only. Domabas checks device
support and camera permission before opening VisionKit and returns to the saved
draft on cancellation. The system controls camera selection and image cleanup;
Domabas does not impose the custom camera's exposure or focus settings. See
[Apple's document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller).

VisionKit can return several pages. The draft shows how many of its 20 slots
remain. Apple's public API has no page-limit option, so a result exceeding that
capacity fails explicitly before any returned page is imported. Pages are never
silently truncated. Accepted pages are read, encoded and saved in their original
order, one at a time. VisionKit returns images rather than JPEG files; the native
adapter normalizes orientation and encodes each image once at JPEG quality 1.0.
The draft and PDF preserve those encoded JPEG bytes without further lossy encoding.

The native session retains unread pages while the app imports them. A failed
read or local save pauses the batch and offers retry or explicit discard of the
remaining scans. Already saved pages remain in the draft. Upload and another scan
are blocked while pages remain pending. Leaving warns that unsaved scans will be
discarded; only committed draft pages survive app termination or sign-out.
Temporary backgrounding preserves an active scan or paused batch. Scope closure
cancels its request and drains owned work before camera handoff. The app bounds
its channel output and processes one page at a time, but cannot limit the system
scanner's internal camera memory or page collection before it returns.

## Capture adapters

`ScannerCamera` and `ScanDraftRepository` are the scanner's domain ports.
`ScanCaptureDataPort` lets the local repository obtain page assets from either
capture adapter. Both production adapters return processed pages. App composition
selects the platform adapter. Optional batch and system-capture capabilities
describe pending pages and provider guidance without exposing platform types.
Immutable domain values describe camera state, captures, geometry, pages and
draft outcomes. `ScannerCubit` owns interactions and operation state. Native
camera, detector, files, image correction and PDF generation remain in scanner
data adapters. No plugin or generated API value enters the domain.

The batch adapter assigns a stable capture identity to each native page. Only
acknowledgement after the repository returns success advances the page cursor;
ordinary capture-release calls do not advance it. A retry after a committed save
whose snapshot or cleanup failed reaches the repository's existing identity
check, preventing duplicate pages. One scratch allocation is reused sequentially.
The Android and iOS adapters share JPEG validation and bounded preview generation
while retaining their own native protocol, lifecycle and failure guidance.

The image presenter privately copies immutable domain byte views for Flutter's
codec boundary and reuses its provider while the bounded image bytes are equal.
Property and theme updates therefore do not repeatedly decode the image.
Appearance changes preserve scanner state. The covered document collection
pauses automatic reads while retaining realtime invalidation. A confirmed upload
invalidates the collection through an app callback when read permission permits;
realtime messages never overwrite a local scan or repeat an upload.

## Retained custom-camera fixtures

The custom Flutter camera, detector and correction adapter remain for fixture
coverage. Production Android and iOS capture use their system scanners; neither
falls back to this path. These settings and geometry rules describe the retained
custom adapter, not ML Kit or VisionKit behavior. App composition can supply its
preview builder for tests; data does not return widgets and presentation does not
import the camera adapter.

The custom camera detects page edges during framing. It prefers the rear
wide lens when the device identifies it, requests the highest available capture
resolution and JPEG quality 100, and enables automatic focus while framing.
Automatic flash is disabled to avoid its preflash sequence. Supported cameras
use a -1 EV automatic exposure bias, accepting darker images to reduce the
requested exposure. The camera decides how to divide that reduction between
exposure duration and ISO; this does not enforce a maximum shutter duration.
Unsupported optional settings fall back to the camera's defaults.

After capture, the scanner detects the EXIF-oriented still again and lets the
user adjust four corners before perspective correction. Preview geometry is never
reused blindly for a different still image. The correction view uses a bounded preview; the original pixels stay
behind the camera/data boundary. The original JPEG bytes are retained without
an intermediate re-encode. Correction keeps the source-derived dimensions and
encodes once at JPEG quality 100. Users can add pages, move them earlier or later
in the draft and remove a page before submitting.

Detection first uses the native engine's balanced settings. If no plausible page
is found, `AdaptiveScanDetector` retries once on a detection-only grayscale image, bounded
to 720 pixels on its longest edge. Each pixel is compared with its local mean
brightness, so faint boundaries can remain visible under uneven illumination.
This follows the [adaptive thresholding approach described by OpenCV](https://docs.opencv.org/4.x/d7/d4d/tutorial_py_thresholding.html).
Both passes reject invalid, tiny, extremely thin and almost-full-frame
quadrilaterals, and those that span opposite image borders. The fallback uses the engine's lenient
sensitivity and skips nearly uniform images. It does not change the photo,
corrected page colors or PDF pixels.

Fallback preparation runs in an isolate. Camera input preserves BGRA/YUV row
strides, full-image proportions and rotation; still input uses the already
prepared upright preview. Cancellation and orientation changes prevent further
fallback work and discard late results. The fallback remains part of the single
in-flight detection operation, so frames cannot build up while it runs. It may
reduce the overlay refresh rate in difficult scenes. Corner adjustment remains
available when contrast is insufficient or another rectangular object is found.

The live camera uses the available screen body independently of the review form's
width limits. Bounded, scrollable guidance and safe-area actions leave the rest
for a contained camera image and its outline. The live image has no correction
handle inset. Different sensor and screen proportions can leave dark bands;
the full framing area remains visible in portrait and landscape. Correction
retains its whole-image geometry and accessible corner controls. Users can drag
the numbered corners or any side of the correction outline. Each side has a
visible midpoint grip and a 48-point-wide touch region; corner targets take
priority where they overlap. Dragging a side moves its two corners together,
preserving its angle and length at the image bounds. The bottom sliders remain
available for precise corner adjustment. Invalid or crossed selections disable
Keep page until corrected.

Only one custom-camera frame detection runs at a time, with a minimum 100 ms
interval. Camera
shutdown drains actual initialization and detection work. A captured correction
image has a separate lease from the camera controller, so backgrounding can
release the camera while preserving correction. Discarding or closing waits for
active work before deleting its input. Generation and orientation checks reject
stale frame results. App composition coordinates camera handoff across sessions.
Capture stops admitting live detection immediately and requests the photograph
before stopping the stream or draining the current detector. Storage admission
and camera settings complete before the capture button becomes ready. The
reserved scratch allocation transfers to the captured image at shutter time,
so pressing capture does not wait for a filesystem capacity scan. Startup
interruption releases unused reservations; correction retains its own capture
allocation across camera suspension. Camera state distinguishes capturing (hold steady)
from processing (the platform has returned the still file). The live detector
still drains before still detection and camera disposal. These phases do not
measure sensor exposure time or promise a particular device shutter latency.
If a camera negotiates different preview and analysis aspect ratios, live corners
are hidden with capture-and-adjust guidance. The plugin exposes no crop relation
that would make those coordinates reliable. Still detection and correction remain
available, and the preview retains its own dimensions.

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

The scanner accepts at most 20 pages. System-scanner JPEGs are checked against
18 MiB and 50 million pixels before decoding. The retained custom camera accepts
input stills up to 40 MiB and 50 million pixels and preserves dimensions derived
from the selected corners. Saved JPEGs have at most 50 million pixels and 18 MiB per
page and 98 MiB combined. Oversized pages fail explicitly instead of being
silently downsampled or compressed at lower quality. More detailed pages can
therefore fill a draft with fewer pages. Thumbnails and correction
previews are bounded separately. The PDF preserves image proportions and page
order and embeds the corrected JPEG pixels without another lossy encode, with a
physical longest edge at most 842 points and a 100 MiB file ceiling. The combined
page limit leaves 2 MiB for PDF overhead. Saved upload attempts use the same
100 MiB ceiling when restored or retried.
Storage admission accounts for durable files, temporary work and pending cleanup;
it allows 200 MiB per owner for pages, thumbnails, manifests and the cached PDF,
with a 256 MiB global ceiling, and never evicts another owner's draft.
Scratch admission covers one 40 MiB input,
one 18 MiB corrected image and their bounded previews. Image work is serialized;
full-resolution decoding and perspective correction still need memory
proportional to the camera's negotiated image size.

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

Android pins `play-services-mlkit-document-scanner` 16.0.0 directly in the native
app. Google Play services supplies its scanner UI and models; the application
does not bundle those models. Android release rules preserve the no-argument
constructors of Firebase component registrars used to initialize ML Kit through
reflection. The pinned transitive `firebase-components` version does not include
the complete constructor keep rule needed by the Android build's strict R8 mode.
Keep the targeted rules in `android/app/proguard-rules.pro` when changing release
optimization settings. See the [upstream constructor rule](https://github.com/firebase/firebase-android-sdk/pull/6044).
The production iOS scanner uses Apple's system VisionKit framework, available
within the existing iOS 15 deployment target, without a third-party wrapper.
The retained custom scanner uses the pinned `document_scan` wrapper and Apple's
system Vision framework. The wrapper also includes an Android OpenCV detector in
its package dependencies. Neither production capture adapter invokes the wrapper.
Vision and VisionKit are operating
system frameworks.
The Dart `pdf` encoder creates image-only output. Skia's C++
PDF backend would require separate native bindings and binaries and is not the
encoder used here.

Exact package versions are recorded in [pubspec.lock](../../../frontend/pubspec.lock).
The [platform guide](platforms.md) explains native dependencies and permissions.
Native custom-camera fixtures can prove detection and correction for their input
images; they do not exercise the production system scanner. Builds, browser tests
and geometry tests do not prove camera permission, physical capture or native
review behavior. The [testing guide](../../development/testing.md)
keeps those device checks separate.
