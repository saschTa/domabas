# Third-party notices

This directory keeps license notices for software and models shipped with
Domabas. It is an inventory for maintainers and distributors; the original
license files remain the authoritative terms.

[Document processor](#document-processor) · [Frontend PDF viewer](#frontend-pdf-viewer) ·
[Email ingestion](#email-ingestion) · [Realtime transport](#realtime-transport) ·
[Android embedded notices](#android-embedded-notices) · [Linux dbus source](#linux-dbus-source) ·
[Artifact notices](#artifact-notices)

## Document processor

The processor image retains these upstream notices under
`/usr/share/doc/domabas/third-party`. Tesseract and Leptonica source notices are
also copied from the verified source builds to `/usr/share/doc/domabas/ocr`.
Debian runtime-library notices remain under `/usr/share/doc/` in the image.

The shipped PDFium binary is the WebAssembly artifact embedded in
`github.com/klippa-app/go-pdfium` v1.20.3. Its SHA-256 is
`9b5bdb3ad4bb715420d7e478cc4255ab29d8fe808740c45b3b58e4a7617cb5a0`.
The [wrapper release](https://github.com/klippa-app/go-pdfium/releases/tag/v1.20.3)
identifies PDFium 8057. The matching upstream source revision is
`a5a7089234f121990b336b3841008009dca143bf`.

`pdfium/LICENSE` and `pdfium/licenses/` come from the matching
[8057 distribution](https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/8057/pdfium-wasm.tgz),
whose archive SHA-256 is
`4c7cf42cc4ebe6f5eb0a44cc9d0d1dc1cde8dcd094a5003e229a1bac2d56b0aa`.
Only its notices are used. Its JavaScript-targeted binary is not shipped.
The Go wrapper, wazero (including its NOTICE), and the Apache-2.0 Go commons-pool
dependency notices come from their pinned module distributions.

[`pdfium/licenses/README.ijg`](pdfium/licenses/README.ijg) is a byte-for-byte copy
of [`pdfium/licenses/libjpeg_turbo.ijg`](pdfium/licenses/libjpeg_turbo.ijg), retained
under the compatibility filename linked by the unchanged upstream
[`libjpeg_turbo.md`](pdfium/licenses/libjpeg_turbo.md) notice. The license inventory
continues to use the original `libjpeg_turbo.ijg` path.

The supplemental Emscripten 6.0.9, musl, libc++, libc++abi and compiler-rt notices
come from the [Emscripten source](https://github.com/emscripten-core/emscripten/tree/6.0.9).
The nearest upstream standalone-build recipe is fork commit
`85ae559af5b2afe3fdd728800f4d0790cc760840`; its MIT notice is retained too.
That recipe's relation to the embedded build is inferred from upstream history.
Upstream has not published an exact build attestation for the custom-patched
standalone artifact. This inventory identifies pinned shipped bytes and retains
matching and supplemental notices; it does not claim reproducible compilation.

Tesseract 5.5.3 and the selected `tessdata_fast` 4.1.0 weights use Apache-2.0;
Leptonica 1.87.0 uses its BSD-style notice. Ollama 0.34.1 uses MIT, and the
Nomic v1.5 model has its own Apache-2.0 license. Runtime and model licenses are
separate. The model notices in `models/` come from the exact researched versions.

See [document ingestion](../docs/arch/backend/document-ingestion.md) for the
processor design. The pinned module versions are in [`backend/go.mod`](../backend/go.mod);
the processor build and model verification inputs are in
[`infra/document-processor/Dockerfile`](../infra/document-processor/Dockerfile) and
[`document_pins.go`](../backend/internal/data/document/datasources/processor/document_pins.go).

## Frontend PDF viewer

The frontend independently uses pdfrx 2.6.1 and PDFium chromium/7811. Its bundled
Wasm SHA-256 is `5b2cbb18e9dc361dae375e971c7e75f7306d39b7749ad4fced475579e6a549df`,
identical to the Wasm in the official
[7811 distribution](https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F7811/pdfium-wasm.tgz).
The archive SHA-256 is `e048a2a3c571055f471f5afec1a13f76fece22332bce42c8d45789518c721abf`;
it matches the official GitHub release asset digest.

That archive's complete `LICENSE` and `licenses/` files are combined verbatim in
[frontend-pdfium.txt](../frontend/assets/licenses/frontend-pdfium.txt). The Flutter
asset is included in web and native distributions and registered in the app's
license registry. pdfrx and Bloc wrapper MIT notices are collected from their
pinned package distributions. The backend's 8057 notices remain separate.
See the [document viewer guide](../docs/arch/frontend/documents.md) for how the
viewer is used and [`frontend/pubspec.lock`](../frontend/pubspec.lock) for the
pinned frontend packages.

## Email ingestion

`email/` retains the exact module-distribution license files for the pinned
`github.com/emersion/go-imap/v2`, `github.com/emersion/go-message` and
`github.com/emersion/go-sasl` modules. The backend image already copies this full
directory into `/usr/share/doc/domabas/third-party`. See
[email ingestion](../docs/arch/backend/email-ingestion.md) for protocol and resource
limits, and [`backend/go.mod`](../backend/go.mod) for the pinned module versions,
including the IMAP prerelease.

## Realtime transport

The backend pins coder/websocket v1.8.15 under ISC; its original notice is retained
in [realtime/coder-websocket-LICENSE.txt](realtime/coder-websocket-LICENSE.txt) and
copied with other backend image notices. Flutter pins web_socket_channel 3.0.3
and locks web_socket 1.0.1, both BSD-3-Clause. Their original notices are retained
under [realtime](realtime/) and included by Flutter's package license registry.
See [backend realtime](../docs/arch/backend/realtime.md) and
[frontend live updates](../docs/arch/frontend/realtime.md) for transport behavior.
The Go module and Flutter lockfile record the pinned versions.

## Android embedded notices

The Android scanner pins Google ML Kit Document Scanner 16.0.0. Its scanner and
common runtime have [ML Kit terms](licenses/native/ml-kit-TERMS.txt); the selected
Google Play services libraries declare the [Android SDK license](licenses/native/google-play-services-TERMS.txt).
The supplemental inventory records exact POM declarations and selected runtime
versions, including Apache-licensed transport and Firebase support libraries.
The scanner UI and models are supplied by Google Play services rather than
bundled by Domabas. These Google components have terms separate from Domabas's
MIT license. See [scanner behaviour](../docs/arch/frontend/scanner.md) and
[privacy](../docs/development/privacy.md#what-other-services-receive).

CameraX camera-core 1.6.2 includes statically linked libyuv. The
[CameraX release source](https://developer.android.com/jetpack/androidx/releases/camera#1.6.2)
is AndroidX `9046f07948c1e7a89aaec581463730f4d666611b`; its CMake target links
`libyuv::yuv`. The [matching release manifest](https://android.googlesource.com/platform/manifest/+/3feefa495c15c5fdf0339cb58e52e73629d5a92e/default.xml)
pins that source and libyuv `afae031e789e344bfc34c9e763c83f861a1ff3f1` together.
The original [libyuv LICENSE](licenses/native/camera-core-libyuv-LICENSE.txt),
[PATENTS grant](licenses/native/camera-core-libyuv-PATENTS.txt) and
[AUTHORS](licenses/native/camera-core-libyuv-AUTHORS.txt) are retained verbatim
from that revision, alongside the existing camera-core Apache notice.

DataStore `datastore-preferences-external-protobuf` 1.1.7 relocates
`com.google.protobuf` to `androidx.datastore.preferences.protobuf`. Its
[release source](https://developer.android.com/jetpack/androidx/releases/datastore#1.1.7)
is AndroidX `420da5f291449f11801e378c6789a328a06ec6cb`. The module's build recipe
and version catalog select `protobuf-javalite` 4.28.2, corresponding to upstream
Protobuf v28.2, commit `9fff46d7327c699ef970769d5c9fd0e44df08fc7`.
The [original Protobuf LICENSE](licenses/native/datastore-protobuf-LICENSE.txt)
is retained verbatim from that commit.

Both notices keep their actual copyright holders. The existing Maven entries in
[the supplemental catalog](licenses/supplemental.json) record immutable source
addresses and notice hashes; the generated catalog and Flutter asset include
these complete texts.
Recheck the resolved Gradle graph and packaged APK whenever native dependencies
change. Verify notices and source obligations for each published artifact.

## Linux dbus source

The Linux desktop integration uses the unmodified `dbus` 0.7.15 Dart package
under MPL-2.0. Its original [LICENSE](licenses/sources/dbus/0.7.15/LICENSE)
is retained here; the source archive is not bundled in this repository.
Recipients can download that exact source without charge from
[pub.dev](https://pub.dev/api/archives/dbus-0.7.15.tar.gz). Its SHA-256 is
`a48d5da28e89bd02196e80d81ed8d7954923d00a0f4a68cc20b575038f023383`, matching
the [frontend lockfile](../frontend/pubspec.lock) and
[official version metadata](https://pub.dev/api/packages/dbus/versions/0.7.15).
The archive includes the source, package metadata, tests, examples and original
notices. Compare its contents with the resolved package before redistribution.

The [retrieval notice](licenses/sources/dbus/0.7.15/retrieval.txt) appears inside
the existing `dbus` entry in **User settings → Licenses**, alongside the original
MPL text. Its full download address is selectable and copyable offline; downloading
the source itself requires network access. The supplemental manifest uses
`appendTo` to add notices to the exact existing package version without replacing
its metadata or adding another component.

Distributors must still keep the covered source available to recipients of
releases containing it. Verify the advertised download remains available and
provide the exact source at a maintained address or with release materials if
needed, updating the retrieval notice accordingly. If `dbus` changes, make the
new exact source, including any modifications, available and update its version,
checksum and retrieval notice before distributing the new build. Keep source
notices and recipients' MPL rights intact. See
[MPL sections 3.1–3.4](https://www.mozilla.org/en-US/MPL/2.0/) and
[Mozilla's FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/); separate application
files may keep their own license. The upstream link is a retrieval reference,
not verification of distribution compliance. Actual Linux release packaging
remains a separate validation step.

## Complete inventory and app screen

Use the small **Licenses** button at the bottom right of the sign-in, account
recovery or native first-run server setup screen to read notices before signing
in. After signing in, open **User settings → Licenses** (the More/settings chooser
on phones). Both paths let you search components and read their retained notices
without a backend connection. Web needs an initial page and asset load before
offline reading. This adds Go, Bun, native, model and infrastructure evidence to
Flutter's existing registry.
The [generated inventory](licenses/INDEX.md) links exact package identities.
Review copyleft obligations, missing grants, vendor conditions and binary coverage
for each distribution. This source inventory is not commercial distribution
clearance.

`licenses/catalog.json` is the retained evidence snapshot, with full notice texts
indexed by SHA-256. All four project images copy `third_party/`, so the catalog
accompanies each distribution. Flutter includes the generated
`assets/licenses/third-party.json`, including the Domabas MIT license from the
root `LICENSE` file. Licenses and NOTICE files are retained from
Go module directories, Dart package caches, installed Bun packages, exact-version
npm mirrors for optional platforms, checked-in notices and the explicit upstream
sources in `licenses/supplemental.json`. Labels are search aids, not a legal
interpretation of every embedded notice. Important mixed distributions have
explicit summaries in that manifest, including Bun's statically linked LGPL
components, LLVM exceptions and PDFium's bundled libraries. Wrapped license
text is recognized without treating copyleft compatibility references as grants.
Missing license evidence remains marked for review; a label is not distribution
clearance.
Git permits trailing blank lines in retained native notices so upstream license
files can remain byte-for-byte unchanged.

To regenerate/check the app asset and Markdown index from retained evidence:

```sh
task generate:licenses
task generate:licenses:check
```

After a dependency change, resolve the pinned caches with `task setup` and
`go -C backend mod download all`, review/update supplemental sources and native
resolution, then run:

```sh
task generate:licenses -- --collect
task generate:licenses:check
```

The full Go graph includes dependencies of tools and their tests. Downloading it
adds missing checksums to `backend/go.sum`; review and retain those checksum-only
changes. Collection reads every Go graph module, every resolved Dart package and
every Bun lock entry, including optional packages for other operating systems.
It fails on missing caches or failed downloads; a package with no discovered
license stays marked for review. Do not replace missing evidence with an assumed
MIT/Apache license. HTTP notice responses are cached by URL in
`.cache/license-audit/`; remove that disposable directory to re-fetch upstream
text. Retained catalog text hashes and input fingerprints are verified offline.

Resolve Android coordinates for `licenses/android-resolution.json` by running
`./gradlew --offline --no-daemon -q :app:dependencies --configuration releaseRuntimeClasspath`
from `frontend/android` with `JAVA_HOME` set to the local JDK.
Re-resolve after native dependency changes, compare selected coordinates and
update their exact POM/parent-POM evidence in `licenses/supplemental.json`.
The normal generator intentionally does not claim to resolve every native SDK or
OS image. Review each release artifact's dependencies and notices separately.

`task check` and GitHub CI run the offline consistency check. A change to a repository
dependency input fails until the evidence is refreshed. New, unignored inputs are
also checked before staging, including GitHub workflow files. New downloaded binaries,
fonts/models and optional deployment images must also be added to the supplement
manifest with their own notices and provenance.

## Artifact notices

Each independently distributed app retains the generated catalog in its Flutter
asset bundle. The backend, web, document-processor and init image recipes copy
the Domabas MIT license to `/usr/share/doc/domabas/LICENSE` and the complete
retained third-party directory to `/usr/share/doc/domabas/third-party/` in their
final stage. The processor additionally retains OCR notices under
`/usr/share/doc/domabas/ocr/`. Upstream OS notices remain in their original paths.
The catalog includes development and optional components as well as runtime
dependencies; it is not a list of everything linked into each individual image.

`task release` checks `task generate:licenses:check`'s offline consistency rules
before building or publishing. Run that check for releases made through other
paths too. For every built app, verify the packaged catalog matches the current
asset and read notices with the backend unavailable. Web needs an initial page
and asset load; this does not promise a first visit without network access.

For each final image, inspect the retained files without starting the service:

```sh
container=$(docker create --entrypoint /bin/true YOUR_RELEASE_IMAGE)
docker cp "$container:/usr/share/doc/domabas" ./release-notices
docker rm "$container"
```

Compare the extracted license and catalog with the release checkout, and inspect
the relevant upstream OS notices. Standalone executables distributed outside
these images must be accompanied by the root `LICENSE` and this notice directory.
Retaining notices does not establish complete binary license coverage or satisfy
separate source-delivery obligations.
