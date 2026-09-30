# Frontend platforms and transport

The Flutter app shares its document screens and domain logic across Android, iOS, web, Linux, macOS and Windows. Each platform directory supplies the host application and build configuration. The domain and presentation layers do not depend on those platform files.

## API transport

The composition root owns and disposes the HTTP client. The API data source uses the generated Dart client, and the repository maps transport data to domain objects. Generated decoding can fail through runtime casts or debug assertions when fields are missing; the adapter translates those failures into the same domain error. The UI receives a stable error vocabulary rather than generated DTOs or raw server messages.

Web builds use their browser origin unless an API URL is supplied explicitly. The Compose web server forwards those requests to Go. Native apps remember a server selected during setup; an explicit `API_BASE_URL` supplies an initial development default. See [server configuration](server-configuration.md). The browser E2E test discards the view state and HTTP client before reading again, so it checks persistence rather than a cached result.

For local HTTP browser development, an API configured as `localhost` or
`127.0.0.1` uses the page's hostname when the page also uses either alias. The API
port and path remain configured. This keeps persistent cookies on the same site
when opening either development URL. Native, HTTPS and other explicit endpoints
remain unchanged.

## Android certificate trust

Android release and debug builds trust both system CAs and CA certificates that
the user installs in Android's trusted credentials. Android's network security
configuration declares both sources. A background platform channel reads the
configured `X509TrustManager` CA certificates as a PEM bundle. Dart's default
Android root loader reads only a system certificate directory, so the app loads
that bundle into a separate `SecurityContext` for each Android HTTP client.
The app does not mutate global TLS state or accept invalid certificates.

The app composition root supplies this client policy to readiness probes, public
and authenticated API clients, document transfers and realtime WSS handshakes.
Certificate loading has a five-second deadline and failures become transport
errors. Concurrent HTTP requests share their client's initialization. Closing a
client or aborting a realtime attempt during loading closes any late-created
client before it connects. Android's channel belongs to the Flutter engine and
is detached when that engine is cleaned up.

Trust is a snapshot for the lifetime of each client. Restart the app after adding
or removing trusted CAs so every existing client receives the current store.
Certificates must still be valid for the server hostname and current date, and
the server must present the necessary certificate chain. Untrusted self-signed
servers remain rejected. Install the issuing CA as a trusted CA, rather than as
a client identity or Wi-Fi certificate; see [server setup](server-configuration.md).

The debug resource override preserves local HTTP development. Release/profile
configuration keeps HTTPS policy. Other native platforms retain their existing
certificate stores, and browsers retain browser-managed trust. See
[server setup](server-configuration.md) for connection checks and endpoint ownership.

## Persistent session storage

The `SessionStore` domain port supplies credentials for server validation; it
never stores identity, roles or permissions. App composition selects an adapter
through `persistent_session_store.dart`. Keys include the canonical API origin
and path, so separate installations do not share credentials.

Native clients use pinned `flutter_secure_storage` 11.2.0. Android uses its
non-biometric RSA OAEP/AES-GCM configuration in the `domabas_sessions_v1`
namespace, with automatic destructive reset and algorithm migration disabled.
The shipped plugin requires Android API 24 even though its README discusses
API 23 cipher support. Backup rules exclude the data, wrapped key and algorithm
preferences from cloud backup and device transfer. iOS uses unlocked,
device-only Keychain entries without iCloud synchronization or shared app groups;
all three Runner configurations select `Runner.entitlements`. The resolved
Darwin plugin supports iOS 13; Domabas keeps its existing iOS 15 deployment target.

Native operations have a five-second caller deadline. Operations remain ordered
until the underlying platform call settles, even after a timeout. A late token
write therefore cannot overtake a later logout deletion. Writes and deletes are
read back before success. Storage errors become a stable unavailable failure;
there is no plaintext fallback. Linux needs libsecret and an unlocked Secret
Service keyring. Windows uses the plugin's platform-protected storage and requires
C++ ATL libraries when building.

Browser restoration uses the server's HttpOnly cookie. The browser adapter never
stores a token in JavaScript storage and does not call the secure-storage plugin's
web implementation. Its only localStorage value is a nonsecret signed-out marker.
Logout writes this marker before server revocation, so offline logout suppresses
cookie restoration. A successful sign-in clears it. Storage denial blocks restore
with a retryable error. Clearing site data can remove the marker and cookies;
browser retention remains outside the app's control.

Session restoration and teardown are covered by the
[identity lifecycle guide](identity.md).

## Platform hosts

All six targets use the selected Filed Paper mark. See
[application branding](branding.md) for the vector master, platform exports and
regeneration checks.

System, Light and Dark appearance is stored separately from authentication with
pinned `shared_preferences` 2.5.5 on all six platforms. The client keeps working
when preference storage is unavailable and offers retry. See
[appearance and client preferences](appearance.md) for the storage locations,
ordering and scope.

Android applies Flutter's Gradle plugin after the Android plugin and takes SDK/version values from Flutter. Its current release build configuration uses development signing; store distribution needs separate signing setup. Debug manifests permit local development networking. Android styles and drawable files control the launch background and the transition to the Flutter view.

GitHub releases publish containers only. Android, iOS and desktop targets remain
available for local development, with no native downloads or CI build claim.
See the [release support table](../../development/releases.md#supported-artifacts).

iOS keeps development networking settings separate from release settings. App delegates, storyboard files and Xcode project settings supply the native host. Store distribution needs signing and application identifiers.

macOS uses a sandboxed Cocoa host and Swift Package Manager plugin integration.
Debug/profile and release builds permit outgoing API connections and read access
to user-selected files. Only debug/profile permits incoming debugger connections
and JIT execution. Session storage uses the local, non-shared macOS Keychain
with `usesDataProtectionKeychain: false`; no Keychain Sharing provisioning profile
is required. The file chooser supports uploads; drag-and-drop and camera scanning
are not enabled on macOS. See the [frontend commands](../../../frontend/README.md)
for host-specific builds.

Linux uses a GTK host. It selects a header bar for GNOME and Wayland, and a normal title bar for other X11 environments. It shows the window after Flutter renders its first frame. Run the installed application bundle: its libraries and assets must keep their relative locations.

Windows hosts Flutter in a Win32 window. The host accounts for display scaling, forwards window messages to Flutter and follows the system theme. It requests a frame after installing the first-frame callback so an earlier frame cannot leave the window hidden. Command-line conversion bounds UTF-16 input before allocating the UTF-8 buffer. Resource files carry the app icon and version information.

Desktop CMake files run Flutter's build step even when its full input list is not known, then copy current libraries and assets into the application bundle. Flutter-owned generated plugin registrants and build outputs are maintained by the SDK. Their generated-file and tool annotations are not handwritten product documentation.

See the [platform build guide](../../development/index.md#native-targets) for host requirements and commands.

## Mobile scanner

Camera scanning is available on Android and iOS. The camera permission is requested
when entering capture; both iOS property-list configurations describe its purpose.
Android keeps API 24 as its minimum and does not require Google Play Services for
edge detection. The native detector uses OpenCV on Android and the installed
Vision framework on iOS. Unsupported targets do not initialize these plugins.

The app owns the camera preview bridge and coordinates controller handoff. Durable
draft storage is scoped to the API endpoint, user and library and survives signing
out. Android backup rules preserve the existing secure-session exclusions; iOS
marks the scanner root as excluded from backup. See [scanner ownership and limits](scanner.md).

Camera and native dependency changes require Android/iOS build checks. A simulator
can exercise native still detection and correction but cannot validate physical
framing or live camera alignment. Check those on a camera-capable phone, including
both landscape orientations, permission denial and background/resume. The
[scanner guide](scanner.md) describes dependencies and device validation limits.

## Document rendering

The document viewer pins pdfrx 2.6.1, pdfrx_engine 0.6.0 and the PDFium wrappers
0.3.0 through the committed lockfile. PDFium reads/rasterizes PDFs; Skia's PDF
backend generates PDFs and is not the reader used here. Flutter decodes PNG/JPEG
and displays rendered pages. The application keeps all six platform hosts.

Web builds include the package's PDFium 7811 Wasm and JavaScript worker assets
on the app origin. Repository web builds disable Flutter resource CDNs as well.
The engine therefore needs no external host at document-open time; originals still
require the authenticated server. Web and native views use in-memory authenticated
bytes instead of a renderer-managed URI cache. See [workspace ownership and limits](documents.md).

Android/Linux/Windows native assets download a fixed PDFium 7811 release during
builds; the upstream hook does not verify archive hashes. Release validation
compares executed/packaged libraries with the official digest-checked archives.
iOS and macOS use the pinned, checksum-verified XCFramework and require iOS 15
and macOS 12 respectively. Windows
requires Developer Mode for package symlinks. Native build hosts need GitHub
release access and writable Flutter/pub caches. A supported target is not evidence
that its native build or device execution has been verified.

The app bundles the exact matching PDFium/dependency notices in
`assets/licenses/frontend-pdfium.txt` and registers them in Flutter's license
registry. Wrapper packages supply their own MIT notices. Dependency versions are
recorded in [pubspec.lock](../../../frontend/pubspec.lock); see the
[testing guide](../../development/testing.md) for host-specific validation.

## Selecting and dropping originals

Native selection pins `file_picker` 13.1.0 and uses its lazy multiple-file API
without eager bytes or compression. Android/iOS provider cache copies precede
Dart admission and have no plugin-provided size/count cancellation bound. They
remain outside the application's 20-file/100-MiB memory claim; the app never clears
a shared picker cache or deletes a selected source.

The direct browser adapter uses pinned `web` 1.1.1. It owns exact chooser and
capture-phase drag listeners, prevents external file navigation while signed out,
leaves ordinary link/text defaults available, and rejects directory entries
without traversing them. It captures bounded File handles synchronously at drop.

Linux and Windows register the local `desktop_drop` 0.8.4+domabas.1 derivative in
`frontend/packages/desktop_drop`; its README records upstream archive hash,
license and maintained changes. It pins compatible D-Bus 0.7.15 and registers no
web/mobile/macOS plugin. The owned Dart dispatcher captures registration tokens
before one bounded portal RPC. Removal permanently invalidates a token, and RPC
plus client close retain their physical lease after a logical timeout. Windows
negotiates CF_HDROP and copy only, reads exact dynamically sized UTF-16 paths from
the acquired HGLOBAL and releases its medium once. Linux's GTK destination is
copy-only; non-file URI candidates never open a path. Its native hover is an
invitation and explicitly says links are ignored because the motion callback
cannot establish offered file types. Native desktop compilation and physical drag
interaction require their respective Linux/Windows hosts.
