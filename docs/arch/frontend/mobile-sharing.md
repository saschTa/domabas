# Uploading shared mobile files

The iOS and Android apps appear in the system share sheet for documents. This is
another entry point for the existing `documents:upload` claim and
`POST /api/v1/documents/upload`; it creates no new backend authority or endpoint.
Web and desktop acquisition remain platform-specific.

## iOS

`ShareExtension` is an embedded native Swift extension. It accepts up to 20 PDF
or image attachments through `NSItemProvider`, checks the current identity with
`GET /api/v1/auth/session`, and shows the server and library before Upload.
Sign in and select the destination library in Domabas first. The extension cannot
configure a server, sign in or switch libraries itself.

The extension performs the upload inside the share sheet. It does not use a
responder-chain workaround to launch the containing app. Keep the sheet open
until each result appears. There is no durable background upload queue: if iOS
terminates the extension or the connection is interrupted, check the library
before sharing again. The server continues processing originals it has accepted.
Cancelling an in-flight request cannot undo an upload already accepted by the
server. An uncertain response is never automatically retried.

PDF, PNG and JPEG bytes are preserved. Other single-frame images, including HEIC,
are converted with ImageIO to JPEG at quality 0.92, with orientation applied and
the longest edge limited to 4096 pixels. Source images above 50 megapixels or with
more than one frame are rejected. Each original and converted file must fit the
existing 100 MiB limit. Files and multipart bodies are prepared one at a time in
the extension's protected temporary directory, with bounded stream reads and a
two-minute attachment deadline. Abandoned directories older than 24 hours are
removed before another upload. Success,
duplicate, rejection and uncertain outcomes are shown per file. Responses are
limited to 128 KiB; successful receipts must match the file's name, size, SHA-256,
media type, title and uploader. HTTP redirects are rejected.

`ShareSessionStore` reads the same device-only, unlocked Keychain credential as
the containing app. Both signed targets use the main app's existing default
Keychain access group. This preserves existing session entries without copying
bearer tokens to another store. A separate active-context Keychain entry holds the
server, credential key, user/library IDs and token fingerprint. App composition
clears the context during sign-out, session transitions and server replacement.
The extension re-reads the original credential and matches the fingerprint and
context before each send; server identity validation and upload authorization
remain authoritative. Permissions and passwords are not persisted in the context.

The containing app ID is configured in
`frontend/ios/Flutter/Share.xcconfig`. Runner and ShareExtension derive their
bundle IDs and shared Keychain group from it. Both targets must use the same
Apple development team and provisioning profiles that permit that group. The
extension uses only extension-safe APIs and keeps iOS 15 as its minimum. It has
the same user-selected-server HTTP exception and local-network explanation as
Runner. See [the native build guide](../../../frontend/README.md#sharing-from-other-apps).

## Android

Runner's activity handles `ACTION_SEND` and `ACTION_SEND_MULTIPLE` for
`application/pdf`, `image/png` and `image/jpeg`, including cold start and
`onNewIntent`. It reads `EXTRA_STREAM` or URI attachments in `ClipData`.
Text and webpage links are not downloaded; other image formats are not converted
on Android. A sender using a generic mixed MIME type may need to share PDFs and
images in separate batches.

`MobileShareChannel` reads temporary `content://` grants on a worker thread and
copies originals into private cache. It rejects filesystem paths, app-owned
provider authorities, unreadable streams and unsupported signatures. A batch is
bounded to 20 files, 100 MiB per file and 200 MiB total, with a two-minute acquisition
deadline. Only one share batch can be outstanding. A second share asks the user
to finish or discard the first; it does not replace those files.

`MobileShareCubit` belongs to the selected-server app scope. Shared files wait
through initial server setup and sign-in, then show a confirmation naming the
current library. Upload feeds `DocumentUploadCoordinator` and the existing
session-owned queue, transport, receipt checks and progress UI. A batch already
bound to a session is discarded on a library/session change, including a late
native read. Busy and upload-forbidden sessions cannot admit files. Upload-only
sessions do not perform document reads.

Staged files are released after completion, discard or scope teardown. Host
recreation consumes the old intent instead of replaying it; if the app is killed
before confirmation or acceptance, share the files again. The next native channel
initialization removes abandoned staging files older than 24 hours. No storage or photo-library
permission is added; access comes from the sender's URI grant.

## Sources and validation

The implementation follows Apple's [Share Extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html),
[extension lifetime and attachment rules](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html),
and [Keychain sharing model](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps),
and Android's [receiving shared data guide](https://developer.android.com/develop/ui/compose/sharing/receive).
No additional Flutter or native dependency is needed.

See [mobile share checks](../../development/testing.md#mobile-share-checks) for
native builds, automated tests and device acceptance scenarios. Browser E2E
verifies the common upload workflow, but cannot exercise either OS share sheet.
