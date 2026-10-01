# Development

See [runtime resources and memory diagnosis](resources.md) for CPU/RAM sizing,
per-service budgets and recording evidence around a crash.

## Guides

| Need | Guide |
| --- | --- |
| Run the web application on your server | [Compose and self-hosting](compose.md) |
| Build and install a phone or desktop app | [Local app builds, step by step](build-apps.md) |
| Understand stored data, AI sharing and deletion | [Data and privacy](privacy.md) |
| Choose CPU, memory and workload limits | [Runtime resources](resources.md) |
| Configure AI providers and GPU use | [Document AI configuration](property-extraction.md) |
| Connect a mailbox | [Email configuration](email.md) |
| Run tests or prepare a CI runner | [Testing and CI](testing.md) |
| Follow the local planning and change workflow | [Contributor instructions](../../AGENTS.md#change-workflow-and-validation) |

## Toolchain

Repository toolchain and image pins:

| Component | Pin | Source |
| --- | --- | --- |
| Go | 1.27.1 | [Go downloads](https://go.dev/dl/) |
| Flutter / Dart | 3.47.4 / 3.13.3 | [Flutter archive](https://docs.flutter.dev/install/archive) |
| PostgreSQL | 18.6 | [PostgreSQL releases](https://www.postgresql.org/docs/release/) |
| pgvector | 0.8.6 | [pgvector](https://github.com/pgvector/pgvector/tree/v0.8.6) |
| Air | 1.67.4 | [Air releases](https://github.com/air-verse/air/releases) |
| oapi-codegen | 2.8.0 | [oapi-codegen releases](https://github.com/oapi-codegen/oapi-codegen/releases) |
| OpenAPI Generator | 7.25.0 | [Generator releases](https://github.com/OpenAPITools/openapi-generator/releases) |
| Chrome for Testing | 153.0.8010.47 | [Chrome availability](https://googlechromelabs.github.io/chrome-for-testing/) |
| Bun | 1.4.2 | [Bun release](https://github.com/oven-sh/bun/releases/tag/bun-v1.4.2) |
| TypeScript | 7.0.2 | [TypeScript package](https://www.npmjs.com/package/typescript/v/7.0.2) |
| Temporal Server / Go SDK | 1.32.0 / 1.49.0 | [Server release](https://github.com/temporalio/temporal/releases/tag/v1.32.0), [SDK release](https://github.com/temporalio/sdk-go/releases/tag/v1.49.0) |
| Temporal CLI / UI | 1.9.1 / 2.54.1 | [CLI release](https://github.com/temporalio/cli/releases/tag/v1.9.1), [UI release](https://github.com/temporalio/ui/releases/tag/v2.54.1) |
| Nginx | 1.30.5 | [Nginx releases](https://nginx.org/en/download.html) |

Install Task 3.x, Bun 1.4.2, and Docker with Compose v2. Java 17+ is required only to regenerate the Dart client. On macOS, installed Homebrew OpenJDK 21 is detected automatically. `JAVA_HOME` takes priority. Flutter platform toolchain requirements are reported by `task doctor`.

Go's module declares the exact toolchain requirement and keeps development tools in `go.mod`. Flutter dependencies and their lockfile are committed, as are generated API packages and platform scaffolds. `.tool-versions` records Go, Flutter, and Bun for version managers; using a version manager is optional. Bun is also pinned in `.bun-version` and `package.json`. `bun.lock` records exact tooling dependencies.

## Monorepo tooling

Go Task remains the command entry point. Every repository-owned orchestration script under `scripts/` is TypeScript executed directly by Bun. `task setup:tooling` installs dependencies with `bun install --frozen-lockfile`; tasks that need tooling dependencies invoke it automatically, including `task dev` on a clean checkout. `task lint:scripts` runs TypeScript checking, and `task test:scripts` tests the orchestration behavior. `task check` runs both; GitHub CI runs `task check` and isolated PostgreSQL integration. See the [release guide](releases.md) for publishing and initial repository setup.

Scripts are grouped by purpose; the [script directory map](../../scripts/README.md)
lists each folder and its task commands. Tests live beside their implementation.
Run a helper directly with `bun --no-env-file scripts/<folder>/<name>.ts` after
installing tooling dependencies. For example,
`bun --no-env-file scripts/testing/e2e.ts --external-db` exercises the application
against an existing test database. Script roots are resolved from their source
location rather than the caller's working directory.

Bun automatic dotenv loading is disabled in `bunfig.toml` and explicit CLI invocations. The helpers load `backend/.env` deliberately and apply exported overrides. Air receives only ambient environment variables, allowing the backend to reread its own env file on every restart. No implicit root `.env.local` may silently change these rules.

Browser archives are streamed and extracted into temporary directories with path, link, and executable-mode handling. A completion marker is written only after successful installation. On Windows, the batch-command adapter preserves Flutter's normal SDK bootstrap. See [tooling architecture](../arch/tooling.md) for process lifetime, downloads and dependency management.

## Daily loop

Run `task dev` from the repository root. The launcher starts and waits for Compose PostgreSQL, Temporal schemas and namespace, resolves dependencies, starts Air (HTTP and worker), waits for `/readyz`, then starts Flutter at port 7357. Open `http://127.0.0.1:7357` so the browser and API use the same hostname for persistent cookies. Press `r` to reload Flutter or `R` to restart; Air automatically rebuilds on Go/SQL/config changes. Flutter's normal development terminal remains available. `q` or Ctrl+C stops both application process trees. Infrastructure remains running for the next session; `task infra:down` stops it without deleting volumes.

Managed development now uses Compose consistently. `task infra:up` starts infrastructure alone; `task db:up` and `task db:down` operate only on PostgreSQL and its database initialization. The full web stack uses `task compose:up` or `docker compose up --build --wait`. See the [Compose guide](compose.md) for the service graph, ports and configuration.

Select Ollama by changing `OLLAMA_RUNTIME=cpu` in `backend/.env` to `cuda`,
`rocm` or `mlx`, then restart `task dev`. MLX runs a managed native Ollama on
Apple Silicon while the processor stays in Docker. Its process stops with the
development session and its model cache is retained. `task infra:up` stays in
the foreground in MLX mode. See the
[runtime guide](compose.md#select-the-development-ollama-runtime) for prerequisites,
model selection and lifecycle details.

Earlier native `.cache/postgres` clusters are retained but no longer selected automatically. Their records are not silently migrated into the Compose volume. Stop any native server using the configured port before starting Compose: for a PostgreSQL 18 installation, `pg_ctl -D .cache/postgres -m fast -w stop` from the repository root. To keep using that cluster, start it deliberately and use the external-services option with a separately managed Temporal server. Never delete the cluster to resolve a port conflict.

## Configuration

For encrypted IMAP credentials, key rotation and private mailbox servers, see the
[email configuration guide](email.md).
For per-user source setup and automatic credential encryption, see
[Paperless import configuration](../arch/backend/paperless-import.md).

`backend/.env` contains checked-in development defaults. The backend and scripts prioritize exported environment variables. The backend also supports `DOMABAS_ENV_FILE` to choose a different file or an empty string to disable file loading. The stack scripts read `backend/.env` plus exported overrides; when using an alternative backend file, export matching database and Temporal settings for the launcher, or use `--external-services`.

Keep real deployment credentials out of `backend/.env`. Follow the
[private deployment settings](compose.md#private-deployment-settings) workflow
for distinct database passwords in an ignored `.env.deployment.local`, or use
the [private TrueNAS YAML copy](../../truenas/README.md#3-fill-in-your-settings).

| Setting | Default | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | `postgres://domabas:domabas@127.0.0.1:54329/domabas?sslmode=disable` | Backend database |
| `HTTP_ADDR` | `127.0.0.1:8080` | Backend listen address |
| `CORS_ORIGINS` | `http://localhost:7357,http://127.0.0.1:7357` | Exact permitted browser origins |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | `domabas` | Compose initialization |
| `POSTGRES_PORT` | `54329` | Compose host port |
| `TEMPORAL_ADDRESS` | `127.0.0.1:7233` | Go SDK connection to Temporal |
| `TEMPORAL_NAMESPACE` | `domabas` | Workflow namespace |
| `TEMPORAL_TASK_QUEUE` | `domabas-documents` | Task queue polled by the embedded worker |
| `EMAIL_CREDENTIAL_KEYS` | empty | JSON keyring for encrypted IMAP usernames and passwords |
| `EMAIL_CREDENTIAL_ACTIVE_KEY_ID` | empty | Active member of the injected email keyring |
| `EMAIL_IMAP_CA_FILE` | empty | Optional PEM roots for verified private IMAP TLS |
| `EMAIL_IMAP_ALLOWED_HOSTS` | empty | Explicit host allowlist; required for private destinations |
| `PAPERLESS_CREDENTIAL_KEY_FILE` | `DOCUMENT_STORAGE_ROOT/.secrets/paperless.key` | Optional path for the automatically generated, retained import encryption key |
| `PAPERLESS_CREDENTIAL_KEY` | empty | Optional existing base64-encoded 32-byte key; overrides automatic file storage |
| `API_BASE_URL` | `http://localhost:8080` | Launcher passes this as a Flutter dart-define |
| `TEST_DATABASE_URL` | development URL in Task commands | Base database for isolated test schemas |

When changing the database port or credentials, update both the URL and Compose settings. Existing database credentials do not change just because initialization variables change. When changing the API port, update both `HTTP_ADDR` and `API_BASE_URL`. Add the exact origin to `CORS_ORIGINS` if choosing another web port.

For externally managed services:

```sh
export DATABASE_URL='postgres://user:password@localhost:5432/domabas?sslmode=disable'
export TEMPORAL_ADDRESS='127.0.0.1:7233'
export TEMPORAL_NAMESPACE='domabas'
task dev -- --external-services
```

`API_BASE_URL` is a build-time Flutter configuration, never a secret. Without an override, web uses the current browser origin and native apps open server setup. Native apps remember the selected address and expose it through Server before sign-in and Settings → Server afterward. A saved address takes precedence over the build default; `task dev` supplies an initial native API address explicitly. For local HTTP web development, `localhost` and `127.0.0.1` API addresses follow the browser's local hostname while preserving the API port/path, so login cookies work through either URL. A standalone cross-origin build can use `flutter build web --dart-define=API_BASE_URL=https://api.example.test` from `frontend/`. Only local defaults belong in version control.

## Native targets

For personal app builds, follow [the local app build guide](build-apps.md).
The Android, iOS, macOS and Windows tasks resolve locked dependencies themselves
and print the finished app's path. They need only the client build tools; full
`task setup`, Go, Docker and API regeneration are not required. Android defaults
to a debug APK; add `-- --release` for release mode with development signing.
iOS defaults to an unsigned release app; add `-- --simulator` for a simulator
debug app, or follow the guide's Xcode signing steps to install on a phone.

Build the macOS app with `task build:macos`; the release bundle is
`frontend/build/macos/Build/Products/Release/domabas.app`. Run it during development
with `task dev -- --device macos`. Building requires macOS, full Xcode selected
with `xcode-select`, and access to the native plugin downloads. The host uses
Swift Package Manager and the committed Dart dependency lockfile. Distribution
signing and notarization require separate Apple release credentials.
The deployment target is macOS 12 or later. To select an installed Xcode for one
build without changing the global toolchain, use
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer task build:macos`.

All six platform hosts are generated. Android requires the Android SDK command-line tools and accepted SDK licenses. iOS requires macOS and a complete Xcode toolchain selected for Flutter and its nested native build hooks. Check the selection before resolving plugins and building:

```sh
xcode-select -p
task build:ios
```

The selected directory must belong to full Xcode, not just Command Line Tools.
The `objective_c` native build hook filters `DEVELOPER_DIR`, so setting that
variable only for Flutter is insufficient when the global selection is Command
Line Tools. Plugin resolution also needs full Xcode visible to enable Swift
Package Manager. See [native platform requirements](../arch/frontend/platforms.md)
for session storage and host dependencies.

Android supports API 24 and later; session preferences are excluded from backup and device transfer. iOS retains its iOS 15 minimum and uses the Runner Keychain entitlement for device-only session storage. Linux builds require Linux with clang/CMake/Ninja/GTK development packages and `libsecret-1-dev` (libsecret 0.18.4 or later). Install `libsecret-1-0` and a working Secret Service provider, such as GNOME Keyring, to run the desktop app; its keyring must be unlocked for sign-in persistence. Windows builds require Windows with Visual Studio's C++ desktop workload, the optional C++ ATL component and Windows SDK.

Use `flutter devices` and `task dev -- --device <id>` for a connected target. An Android emulator reaches the host API at `http://10.0.2.2:8080`; set `API_BASE_URL` accordingly. A physical device needs an API address it can reach and an intentional backend bind address. Flutter's web debugger can attach with `--device chrome`; set `CHROME_EXECUTABLE` when Chrome is installed outside its usual location.

See the [frontend guide](../arch/frontend/index.md) for mobile networking configuration. HTTP and HTTPS work in debug and release builds. Native build tasks validate compilation on the corresponding host. GitHub releases distribute containers only; app signing and distribution are outside this baseline.

Live browser connections use the same configured API endpoint and exact CORS origins as the HTTP client. See [live connection deployment](compose.md#live-connections) and [realtime checks](testing.md#realtime-checks).

Optional [LLM property extraction](property-extraction.md) includes administrator
settings, encrypted API keys and CUDA/ROCm Compose overrides.
