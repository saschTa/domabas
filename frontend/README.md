# Domabas frontend

The Flutter app is the document workspace for web, Android, iOS, Linux, macOS
and Windows. It connects to the Go API for documents, search, invoices, private
AI chat, shared libraries and background jobs. Mobile apps can also scan paper
pages into a PDF.

This guide covers local development, builds and tests. Start with the
[development setup](../docs/development/index.md) for tools, or the
[frontend architecture](../docs/arch/frontend/index.md) for code organization.
This checkout uses Flutter **3.47.4** and Dart **3.13.3**, with dependencies
recorded in [`pubspec.yaml`](pubspec.yaml) and [`pubspec.lock`](pubspec.lock).

User settings → Licenses provides searchable offline notices for the client,
backend, tools and other components. See the [license reader architecture](../docs/arch/frontend/licenses.md)
and [inventory maintenance](../third_party/README.md#complete-inventory-and-app-screen).

## Run the app

From the repository root:

```sh
task dev
```

Open **http://127.0.0.1:7357**. The launcher starts the infrastructure, Go API and
Flutter with hot reload. In the Flutter terminal, press `r` to reload or `R` to
restart. To choose a native target, use `task dev -- --device macos`, or replace
`macos` with an ID shown by `flutter devices`.

If the backend is already running, these commands run just Flutter from this
directory:

```sh
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port=7357 --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

## Choose the server

Web release builds use the browser's current origin by default. The packaged
web server forwards API traffic to Go, so the same image works at different
hostnames. Web has no server selector.

Native apps ask for a server before sign-in and remember it on the device.
Change it through **Server** before sign-in or **Settings → Server** afterward.
Saved sign-ins and scan drafts stay associated with their original server.

`--dart-define=API_BASE_URL=...` supplies an initial native address or overrides
the web default. A native user's saved address takes precedence. This is a build
setting, never a secret. Cross-origin web builds need matching backend CORS
origins; an HTTPS web app also needs an HTTPS API.

Android emulators can reach the host at `http://10.0.2.2:8080`; the iOS simulator
can use host loopback. Physical devices need a reachable LAN address and an
intentional backend bind address. Browser and native release/debug builds support
HTTP, for example `http://192.168.0.230:8088`, as well as HTTPS. Include your
published port and allow local-network access when asked. See [platform networking](../docs/arch/frontend/platforms.md)
and [server configuration](../docs/arch/frontend/server-configuration.md).

## Sessions and libraries

Browser sessions use HttpOnly cookies; native apps use secure storage. Sessions
survive refreshes and restarts and have no routine expiry. Logout, password
changes and access revocation can end them.

Users have personal libraries and can accept invitations to shared libraries.
Library managers assign roles and additional permissions; system administrators
manage system access separately. See [authentication and sessions](../docs/arch/frontend/identity.md).

## Run tests

Unless marked otherwise, run commands from `frontend/`:

| Command | What it checks |
| --- | --- |
| `flutter analyze --fatal-infos` | Static analysis. |
| `flutter test` | All ordinary Flutter tests below. |
| `flutter test test/unit` | Domain rules and presentation state. |
| `flutter test test/structural` | Architecture and import boundaries. |
| `flutter test test/integration` | Client, data source and repository behavior against test HTTP servers. |
| `flutter test test/widget` | Screens, responsive layouts, forms and error recovery. |
| Root: `task test:browser` | Focused tests in the pinned browser. |
| Root: `task test:e2e` | Browser app, real Go API and PostgreSQL together. |

The root end-to-end harness creates its own disposable database schema and task
queue, then cleans them up. An ordinary `flutter test` pass is separate from a
full application end-to-end pass. Use the [testing guide](../docs/development/testing.md)
for service prerequisites and manual browser test commands.

## Build for a platform

For a personal installation, start with the
[step-by-step app build guide](../docs/development/build-apps.md). It explains
tool installation, required first commands, output locations and device signing.
Run these tasks from the repository root. All six hosts are checked in, but a
native build still requires its platform's tools. Android, iOS, macOS and Windows
tasks install locked script and app dependencies automatically; they do not need
`task setup`, API regeneration or a running backend.

| Target | Command | Required host and tools |
| --- | --- | --- |
| Web | `task build:web` | Flutter development host. |
| Android | `task build:android` | Android SDK, accepted licenses and a compatible JDK; produces a debug APK. Add `-- --release` for a release-mode APK using the same development signing key. |
| iOS | `task build:ios` | macOS and full Xcode; produces an unsigned release build, which cannot yet be installed on a phone. Add `-- --simulator` for a simulator debug build. |
| Linux | `task build:linux` | Linux with Clang, CMake, Ninja, GTK and libsecret development libraries. |
| macOS | `task build:macos` | macOS with full Xcode; produces `build/macos/Build/Products/Release/domabas.app`. |
| Windows | `task build:windows` | Windows with Visual Studio's desktop C++ workload, ATL and Windows SDK. |

Run `flutter doctor -v` before native builds. Building a target is separate from
signing and distributing it. See [native setup](../docs/development/index.md#native-targets)
for platform requirements and [Flutter's platform reference](https://docs.flutter.dev/reference/supported-platforms)
for upstream support.

## Update the generated API client

[`packages/domabas_api`](packages/domabas_api/) comes from the
[OpenAPI contract](../contracts/backend/openapi.yaml). Change the contract first,
then run `task generate` from the root. Never edit generated sources by hand.

The generation wrapper uses the pinned OpenAPI Generator **7.25.0**, verifies
its download and finds a local Java runtime. Commit the contract, generated
Go/Dart boundary code and any resulting lockfile changes together. Generated
sources are tracked, so a normal checkout can build without regeneration.
