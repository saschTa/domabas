# Tests and GitHub CI

For memory investigations, use the optional read-only
[`task diagnose:memory`](resources.md#collect-evidence-on-the-affected-host)
while repeating a workload on a disposable stack. The sampler needs Docker
access and a Linux cgroup v2 host with `memory.peak`; its parser tests run in
the existing Bun unit suite without Docker. Soak tests are not part of the
ordinary GitHub checks. Provision the [runtime budget](resources.md) as well
as compiler/browser headroom on runners that start the complete stack.

## Test levels

| Level | Command | What it proves |
| --- | --- | --- |
| Monorepo tooling | `task lint:scripts` / `task test:scripts` | TypeScript checking and Bun tests for configuration, process lifecycle, readiness and artifact handling |
| Backend unit + structure | `task test:backend` | Domain/application behavior, HTTP/config behavior, and import boundaries; race detector enabled |
| Backend integration | `task test:integration` | Real PostgreSQL migrations and repository persistence in isolated schemas |
| Temporal integration | `task test:temporal` | Real queue delivery, repository activity and completion after worker restart |
| Live language model | `LLM_OLLAMA_URL=http://127.0.0.1:11435 task test:llm` | Concurrent real Qwen property extraction and embeddings, plus invoice tax-currency extraction |
| Backend E2E | `task test:api-e2e` | Compiled server subprocess with its worker, public HTTP responses and PostgreSQL persistence |
| Frontend unit + structure + integration | `task test:frontend` | View model/domain behavior, widget interaction, import boundaries, and generated HTTP client/repository against a real local HTTP server |
| Focused browser tests | `task test:browser` | All realtime, scanner, document and upload browser files in one Chrome invocation |
| Full system E2E | `task test:e2e` | Headless Chrome running Flutter integration_test against a real Go server and PostgreSQL |
| Contract consistency | `task generate:check` | Canonical OpenAPI generates exactly the checked-in Go and Dart artifacts |
| Icon consistency | `task generate:icons:check` | The selected SVG generates the checked-in app icons for every platform |
| License inventory consistency | `task generate:licenses:check` | Dependency inputs, locked entry coverage, retained notice hashes and generated offline assets agree |
| Database generation consistency | `task generate:db:check` | Canonical migrations generate exactly the checked-in Jet models and table builders in an isolated schema |
| Compose deployment | `task test:compose` | Container builds, proxied web/API, worker processing, restart persistence and repeated initialization |

Icon generation uses Sharp 0.35.4 with its locked prebuilt native packages for
the runner's operating system and architecture. Bun installs them through the
existing frozen-lockfile step; no global image tool is required. Native Linux
builds also need `glib-compile-resources` from the GTK/GLib development packages.

`task build:android -- --release` builds a local release-mode APK using the
repository's development signing configuration. The native helper's host checks,
locked dependency resolution, failure handling and output validation are covered
by `task test:scripts`. Run the actual build on each target's required host to
verify compilation; tooling tests do not establish native build support. See
[local app builds](build-apps.md) for setup and installation steps.

Native server configuration has unit, generated-HTTP integration and widget
coverage in `task check`. To verify actual preference storage and the native
sign-in screen, start a ready local backend and run from `frontend/`:

```sh
flutter test integration_test/server_configuration_test.dart -d <device-id> \
  --dart-define=SERVER_TEST_URL=http://localhost:8080
```

Do not supply `API_BASE_URL` for this test: it exercises first-run server setup.
Use `http://10.0.2.2:8080` on an Android emulator and a reachable HTTP or HTTPS address on
a physical device. The test restores the previous server preference and makes
only readiness requests; it does not create accounts or modify server data.
iOS requires full Xcode, an installed simulator runtime and simulator signing
with Keychain entitlements. An unsigned build alone does not verify secure
storage. Existing CI fast-test jobs discover the new unit/integration/widget
tests; native runtime checks require the corresponding host and running backend.

`task check` runs analysis, generation consistency, and fast tests, including SDK workflow tests. `task test:all` starts PostgreSQL, Temporal and the real CPU document processor and runs all application test levels. `task test:compose` separately builds and verifies a disposable full deployment. Tagged Go tests deliberately fail when their required database/Temporal/processor configuration is missing. Task loads checked-in defaults; exported overrides take priority. A unique task queue accompanies every disposable database schema, so another test's worker cannot consume its tasks.

`task check` needs no live database. Run `task generate:db` after adding a migration
that changes generated tables, then commit its output. Both database generation
commands require reachable PostgreSQL and a role allowed to create/drop schemas;
they use `TEST_DATABASE_URL` when exported, otherwise `DATABASE_URL` with explicit
local defaults. The pinned Bun SQL client needs no additional package or database
client binary. The pinned Go Jet CLI is installed through `go.mod`/`go.sum`.
The explicit local full Linux check harness checks database generation after its disposable PostgreSQL is ready.

Hybrid search integration tests also need PostgreSQL's bundled `pg_trgm` 1.6.
Migration 013 installs it in `public` using the migration role's database `CREATE`
permission, or validates an operator-provisioned installation. Application test
schemas share the extension and never drop it. The local test commands discover the
new SQL, service, transport and real-processor acceptance tests automatically.

Database tests also require pgvector 0.8.6 installed in `public` by an administrator.
The pinned Compose database image and `database-init` provide it automatically,
including in the full CI harness. External test databases need the same extension;
individual disposable schemas share it and never drop it. Migration tests cover
retained embedding bytes, pending rows, atomic failure and retry. Vector-search
tests compare indexed recall against exhaustive pgvector ranking and check that
the production candidate SQL actually selects the HNSW index. The GitHub integration job provisions the pinned pgvector service. Full local
Linux checks additionally need Temporal and the browser prerequisites.

Identity tests cover credential/session races, forced initial password change,
scoped claim/delegation checks, first-admin and last-admin concurrency, ownership
immutability, personal/shared library isolation, invitation capabilities, session
rotation, revocation and retained migration/adoption. Temporal tests cover queued
v1 failure without an unscoped read and scoped v2 work. Compose smoke signs into
the compiled Flutter app and verifies same-origin authenticated requests.

The integration command discovers `internal/data/...`: document and identity
repositories, document adoption and shared migration tests all run after domain
package moves. Direct SQL fixtures own separate connections to their disposable
schema; production domain sources receive only the borrowed database capability.

Migration integration tests cover fresh/repeated and concurrent startup, legacy
data and timestamp preservation, corrupt ledger rejection, changed/missing/
out-of-order files, transactional DDL and legacy-upgrade rollback, lock-wait
cancellation and retry, and schemas with overlapping document IDs. Tests create
and remove only their own random schemas.

The frontend repository integration suite uses a local HTTP server to test
serialization, extensible claim mapping and errors deterministically. The browser
suite uses the actual generated client, API and database for registration,
personal libraries, invitation acceptance, namespace switching and document
persistence, including fresh app/client state.

The Bun browser harness downloads pinned Chrome/ChromeDriver, creates a random schema, queue and document storage roots, and starts Go at `127.0.0.1:18080`, Flutter on port 7357 and WebDriver on port 4444. It cleans up owned processes and data. Use `bun --no-env-file scripts/testing/e2e.ts --external-services` with `TEST_DATABASE_URL`, `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE` and `DOCUMENT_PROCESSOR_URL` for externally managed services. External mode requires `psql`; managed Docker mode can use its container client. `E2E_API_PORT`, `E2E_WEB_PORT`, and `E2E_DRIVER_PORT` override test ports. Logs remain in `.logs/`. When a development Flutter process already owns port 7357, use `E2E_WEB_PORT=7358 task test:e2e` or another free port; do not stop that development process.

Set `E2E_HOST` to this computer's reachable LAN IPv4 address to run the same browser
workflows over non-loopback HTTP, for example
`E2E_HOST=192.168.0.211 task test:e2e`. The API and Flutter bind to that address;
ChromeDriver remains on loopback. This checks HTTP browser behavior without
localhost's secure-context exception. Only use an address assigned to the test
host; the fixture schema, queues and storage remain isolated.

The diagnostic workflow has a remote execution deadline as well as a client wait deadline. Queue tests use only owned workflow IDs, and stop workers before dropping their schemas. Tests never delete a shared Temporal namespace. Ordinary developer shutdown retains volumes; the full local and Compose smoke harnesses may remove their own explicitly disposable randomly named projects and volumes.

Document pipeline tests distinguish ingestion readiness from downstream AI
completion. API acceptance covers a failed AI provider, searchable documents,
an idempotent AI-only retry, and another upload completing while AI is blocked.
Browser acceptance checks separate pipeline views and retries failed AI from the
document details without changing its ingestion generation. The deterministic
provider fixture needs no external model credentials.
Pipeline scheduling coverage includes configured admission above ten jobs across
two repository instances, email/Paperless priority through execution drain,
provider fifth-attempt recovery and exhaustion, legacy workflow behavior and
effective scheduling metadata on authorized API responses. Frontend tests cover
the scheduling summary at 320 pixels with enlarged text and existing pagination.
The ordinary unit jobs discover the new tests without additional CI services;
`.github/workflows/ci.yml` runs the fast checks and PostgreSQL integration.
The API suite has a 20-minute package deadline because configuration changes
reprocess retained test documents through the bounded AI queue. Individual
ingestion and AI waits keep their shorter deadlines.

Browser cleanup reads the disposable schema's recorded ingestion, AI, email and Paperless executions,
verifies their queue, workflow type and exact run, and stops only those still
running before dropping the schema. It uses an installed `temporal` CLI or the
pinned CLI in an ephemeral Compose initializer container. For an unrelated external
Temporal service, install its reachable CLI on the host; cleanup fails clearly
and retains the schema if execution ownership cannot be verified.
AI workflows use the disposable queue's `-ai` suffix. Cleanup accepts retained
ingestion v1 and split ingestion v2 only with their corresponding ID format.

Email browser acceptance compiles `backend/tests/imapfixture/cmd`, starts a local
implicit-TLS mailbox on a free loopback port and injects its private CA and a
private automatic key-file path into the disposable backend. It tests connection
setup, scheduled retrieval, retained EML, supported attachments, deduplication, email
text/search and private activity through the real API and UI. The fixture uses
only deterministic test credentials; no real mailbox account, OS trust-store
modification or external mail service is required. Runner hosts must permit
loopback listeners and subprocess execution. Fixture processes stop before their
owned certificate, readiness and storage files are removed.

Automatic email-key tests cover concurrent file publication, private permissions,
retained-provider validation, missing-key recovery and explicit-keyring precedence.
The API suite imports mail without injected encryption keys, restarts the compiled
backend and verifies that its saved credentials still authenticate. Compose smoke
checks both private key files and saved mailbox credentials across retained-volume
restart. The local test commands discover this coverage without another service.

Paperless acceptance starts a local read-only API fixture with a random token and
lets the backend initialize its own key under the test's disposable storage root.
No real Paperless repository is contacted and no source allowlist is configured.
The browser test enters the source URL and token, starts an import, leaves Settings, reopens its persisted progress
and verifies imported and unsupported-file outcomes. API E2E additionally verifies
worker restart, transient source overload, pacing, duplicate originals, metadata,
separate users' source URLs, owner isolation, automatic key persistence,
cancellation and credential erasure with real PostgreSQL and
Temporal. Mock repositories cover domain decisions and frontend request lifetime.
These tests use the existing local validation commands and require no additional service.

## GitHub Actions

[The workflow](../../.github/workflows/ci.yml) uses GitHub-hosted `ubuntu-latest`
for pull requests, pushes to `main` and manual release runs. Feature-branch and tag
pushes do not create duplicate pipelines. New commits cancel older runs of the
same PR. Main runs are retained; only publication is serialized.

| Check | Pull request | Main push | Manual run on main |
| --- | --- | --- | --- |
| `task check`: TypeScript, Go vet, Flutter analysis, API/icon/license generation, Bun, Go race/structure and Flutter unit/widget/repository tests | Required | Required | Required |
| `task test:integration` and `task generate:db:check` | Required | Required | Required |
| `task security:dependencies`: critical-only OSV gate | — | Required | Required |
| Build and Trivy-scan four container images, then push and release | — | — | After all checks |
| Temporal, focused Chrome, API/browser E2E, live models and Compose smoke | Local | Local | Local |

Start a release with **Actions → CI and releases → Run workflow**, selecting
`main` and `release_bump` (`patch`, `minor` or `major`). The run checks and
publishes its captured commit. Merges and pushes never trigger publication.
Manual runs on other refs run checks without publishing.

The integration job starts only a pinned pgvector PostgreSQL service. It prepares
shared extensions with `task ci:database`, then uses the existing disposable
schema harness. It has no persistent development volume. The two check jobs run
independently with 30- and 20-minute limits; the dependency scan has 10 minutes.
Cold runner timing must be measured in the first hosted run. The full local
suites remain available for release acceptance and changes that require them.

Go and Bun come from the repository pins. Flutter uses the checksum-verified
installer and SDK cache; pub packages and Go modules/build outputs are cached.
Java 21 is installed for API generation. Third-party actions use full commit
SHAs and tooling dependencies use frozen Bun installation. PR jobs have read-only
repository access, checkout stores no credentials, and no PR job gets release
permissions. No native platform toolchains or app builds are part of this workflow.

`task ci` retains its local units mode. `task ci -- --suite=full` provisions
an isolated Linux stack and adds analysis, generation, database/Temporal tests,
API and system E2E; `--builds` adds local Go, web and Linux builds. This helper is
separate from GitHub's `task check` gate. Full local runners need Docker,
Java and the dependencies installed by `task ci:setup`; model tests need the
resources documented below. Database suites own their schemas and queues.
Compose smoke owns and removes only its randomly named projects and volumes.
Host execution uses loopback; containerized local runners can set
`DOCKER_TEST_HOST` when Docker gateway discovery needs an override.

Focused browser commands have three-minute deadlines. The combined suite uses
one six-minute Chrome invocation; an intermittent Chrome startup stall still
fails the run with diagnostics. Compose smoke has an 18-minute deadline and
keeps its local log at `.logs/compose-smoke.log`. These checks are not automatic
publication gates. Native builds require their corresponding host and toolchain.

See [GitHub releases](releases.md) for version selection, GHCR permissions,
repository activation, retry behavior and vulnerability findings. The
[image gate](releases.md#image-vulnerability-gate) scans locally built images
before the first GHCR push; its reports survive failed publication attempts.

## Document thumbnails

Document thumbnails use the existing fast, PostgreSQL, real Temporal, API E2E and
browser tasks. Rendering fixtures cover bounded JPEG output, EXIF orientation,
transparency, first PDF page, malformed/oversized inputs and child cancellation.
Persistence tests cover minutely discovery beyond one 100-document page, retained
execution ownership, retries and source/deletion races. The API scenario restarts
the backend around automatic generation and checks persisted bytes and namespace
isolation. The document browser scenario waits for automatic thumbnail publication
and inspects resource requests: cards fetch thumbnails, and opening the viewer
fetches its original.

External validation must use a document processor built from this checkout so
the private thumbnail operation is available. An older processor remains ready
for its existing operations but cannot render thumbnails. Test cleanup includes
the schema-owned `-thumbnail` queue and verifies exact workflow type and run before
termination. The GitHub fast-check job discovers the added fast tests without
new dependencies or runner prerequisites.

## Reporting validation

Report the exact checks actually run in the task or pull request report, and
distinguish them from configured CI jobs. Local Flutter web/Go validation does not
prove Windows, Linux desktop, Android or iOS compilation. A GitHub workflow file
alone does not mean a remote pipeline has run.

Keep tracked guides focused on current behavior, commands and requirements.
Working notes and test logs may stay locally in Git-ignored `docs/plans/` and
`.logs/`; never stage or commit them.

Jobs/reindex tests additionally require PostgreSQL, application and Temporal hosts
to have clocks synchronized within one minute and Temporal retention of at least
24 hours. The real processor must be built from the same pipeline manifest as the
backend. Database activity fixtures obtain a real repository admission lease;
unadmitted work is deliberately fenced and has no running deadline. Tests own
only their disposable schemas, task queues, workflow executions and storage.

## Mobile scanner checks

`task test:scanner:web` runs upload validation and actual decoded-image widget
regressions in the pinned Chrome browser. It is part of the full Linux check harness and
`task test:all`, using the same browser libraries and cache prerequisites as the
realtime browser checks. `CHROME_EXECUTABLE=/path/to/chrome task test:scanner:web`
selects an explicit local browser; record its version when using this override.

`task test:documents:web` runs vocabulary transport and Unicode boundary tests,
rendered navigation hover/reversal frames in both themes, and retained thumbnail
image/pixel tests in Chrome. It is additive to scanner and realtime checks and
runs in the full Linux check harness and `task test:all`. It uses the same pinned browser cache and
supports the same explicit `CHROME_EXECUTABLE` override. The real application E2E
also covers automatic search, multiple existing-value pages, immediate filters,
and 360/390-pixel navigation geometry with the application fonts.

Scanner verification separates local persistence, generated document contents,
authenticated submission and physical camera behavior. Temporary-directory tests
must restore committed pages and properties under the same owner, reject another
owner, and cover interrupted writes, corrupt manifests, cached retry bytes and
accepted uploads whose local cleanup fails. All test storage is disposable and
must never point at the user's scanner directory.

PDF tests should inspect actual page count, order and proportions after moving
pages, reopening the draft and deleting a page. Multipart tests must inspect the two actual parts, sparse metadata,
authorization, stalled bodies and ambiguous failures. Browser E2E can inject camera
fixtures through ordinary test composition while using the real PDF encoder,
authenticated upload and backend storage. Production factories have no synthetic
camera switch. Changes to the shared PDF dependencies also require existing viewer
regression checks.

Run the retained custom-camera adapter fixtures from `frontend` with `flutter test
test/integration/scanner_camera_independent_test.dart`. They replace camera
hardware while exercising the custom capture, isolate and crop paths. Production
Android and iOS use ML Kit and VisionKit respectively; these fixtures are not
evidence that either system scanner's camera UI works.
Held detector and shutter futures verify that capture does not wait for live
analysis, preparation starts only after the photo returns, and suspension/closure
drain owned work. Widget tests inspect actual preview bounds on portrait and
landscape tablets as well as accessible page moves in narrow enlarged-text layouts.
The storage fixture also uses `pdfinfo` and `pdftoppm` to independently inspect
PDF pages when both tools are installed (`poppler-utils` on Debian-based runners,
`poppler` with Homebrew). Without them, that external inspection is explicitly
skipped; the production encoder still runs.

`flutter test test/integration/ml_kit_scanner_independent_test.dart` exercises
Android scanner channel results through the production adapter, draft and PDF
encoder. It checks exact JPEG retention, cancellation, foreground transitions,
late results, invalid/oversized images, startup error guidance and retry after
local save failure. These fixtures replace Google's UI; they do not validate the
downloaded scanner itself.

`flutter test test/integration/vision_kit_scanner_independent_test.dart` exercises
iOS batch results through the production adapter, draft and PDF encoder with a
mocked native channel. It covers ordered JPEG retention, one-page-at-a-time reads,
remaining capacity, cancellation, foreground transitions and late results. Failure
fixtures cover read/save retry with stable page identity, explicit discard of
pending pages, image limits, camera handoff and iOS permission guidance. These
tests do not open VisionKit or prove physical camera behavior.

`flutter test integration_test/scanner_native_fixture_test.dart -d <device-id>`
runs the real native detector on a simulator or supported device without opening
a physical camera. Its faint-page fixtures compare ordinary and adaptive detection
on still files and live frame layouts under even lighting and a brightness
gradient, and verify corner positions and empty-scene rejection. Pure adapter
tests in `test/unit/scanner_detection_independent_test.dart` also check strides,
bounded analysis, preview reuse and cancellation between detector passes.
Add `--dart-define=SCANNER_FIXTURE_EXPORT=true` to write temporary
image evidence under the test app's Documents/scanner-fixture-evidence. Flutter's
automatic test-app uninstall can remove that container; the executed pixel
assertions and command log remain the native verification record.
Before returning to Xcode after a native fixture, restore the app entry point
with `task build:ios` from the repository root. The [local app build guide](build-apps.md#macos-and-ios)
also gives a configuration-only refresh command; otherwise Xcode can retain a
temporary test runner path that no longer exists.
The test-only `integration_test/scanner_preview.dart` entry point supports browser
inspection of the scanner UI without changing production platform factories.

Native still fixtures and Android/iOS builds complement phone checks. Use a
minified release APK for Android device checks: debug builds cannot establish
that ML Kit's reflected component registrars survive R8. On real
Android hardware with Google Play services, verify first-use download, native
capture/crop/cleanup, cancellation, return to the draft, repeated Add page,
background/resume and unavailable-services errors. Compare physical scan quality
in bright and dim lighting. The native detector fixtures still exercise the
packaged OpenCV detector, not the production ML Kit scanner UI.
On iOS hardware, verify real VisionKit presentation, capture and its crop/review
controls in both landscape orientations and portrait. Check permission denial,
normal cancellation, background/resume, one-page and multiple-page return, and
the order of pages saved into the draft. Check remaining-capacity rejection,
retry after a paused import, explicit discard of unsaved pages and the leave
confirmation even when a read failure occurs before a preview exists. Verify
that earlier committed pages remain saved, upload/new capture stay blocked while
pages are pending, and only committed pages restore after app restart. Exercise
adding/removing/reordering pages and upload. Compare physical capture sharpness
in bright and dim lighting. The system owns camera settings and image cleanup.

Use a signed install/run path that preserves an existing phone installation and
its data. Flutter integration runners can uninstall their test app; do not run
them against a user's installed Domabas app as a shortcut to camera validation.
A build or injected camera test does not substitute for this checklist. Report
executed checks and
remaining hardware limits in the task or pull request report.
See [scanner architecture and limits](../arch/frontend/scanner.md) for the
production behavior these checks cover.

## Realtime checks

`task test:realtime:web` installs the repository's pinned Chrome and runs strict
frame parsing, transport epochs and physical browser CONNECTING cancellation in
Chrome. The same coverage is part of full local Linux validation and `task test:all`; hosts need
Chrome shared libraries, loopback listeners and writable browser caches. Flutter
VM tests separately exercise native pending-upgrade aborts and state ownership.
An explicit `CHROME_EXECUTABLE` overrides the pinned test browser for local
diagnosis in this command and `task test:e2e`; record the browser version when
using it. E2E retains the pinned ChromeDriver, so choose a compatible browser.

Database integration tests exercise semantic triggers, rollback silence,
namespace/private-owner authorization, listener probes and reconnects. Compiled
API tests start two processes sharing one disposable schema and owned Temporal
queue, then prove cross-process and workflow hints, REST visibility, revocation
and shutdown. Compose additionally verifies the actual proxy for more than its
sixty-five-second timeout. Prompt hint assertions are separate from fallback and
sixty-second safety resync. No new public service or message broker is required.

The original-upload adapter has focused queue/lifetime, native channel and
acquisition/receipt tests. Linux/Windows desktop-drop builds and physical desktop
drag behavior require their respective host toolchains. Linux also requires GTK
and a functioning session D-Bus/file-transfer portal. macOS web/Android/unsigned
iOS builds establish dependency compatibility but do not verify desktop native
interaction or real-device picker/provider permissions. Native provider cache
copies occur before application admission; retain source files and shared caches.

`task test:uploads:web` runs direct DOM chooser/drop acquisition and strict upload
receipt tests in the pinned Chrome harness. It is included in `task test:all` and
the manual full Linux check harness through `scripts/ci/ci.ts`. The suite constructs the
production upload coordinator, exercises exact listener/input cleanup and protects
signed-out file navigation. Set `CHROME_EXECUTABLE` only when deliberately testing
an installed browser instead of the pinned artifact; report that distinction.

## AI chat checks

AI chat is covered by the same unit, PostgreSQL, Temporal, compiled API and browser
commands. The browser model fixture accepts `chat-fixture-model` and exercises
native search/read callbacks against actual document storage. Its tests need no
paid provider account or model download. Chat tests own a schema-specific `-chat`
queue; the test cleanup manifest verifies workflow type, queue and exact run
before terminating retained work. The existing CI unit job discovers the new
provider, workflow, repository-mapping and widget tests without new dependencies.
Full integration remains an explicit local/runner check requiring PostgreSQL,
Temporal and the document processor. `task test:llm` also includes the optional
synthetic Qwen chat protocol check; it requires `LLM_OLLAMA_URL`.

## Property extraction checks

Invoice adapter tests verify that classification and extraction send the accepted
invoice thinking preference, use temperature 0.2, preserve configured context and log the original
prompt and final content. Extraction coverage includes the 50,000-token request
and JSON responses above the former 256 KiB transport cap. Schema and source
evidence validation remain in place.
Provider fixtures verify explicit `think` booleans for native Ollama and
`reasoning_effort` none/medium for external APIs, including LM Studio JSON mode.
Thinking defaults off with existing generation budgets; enabled requests add a
bounded 4,096-token allowance. SQL/Go fingerprints, independent settings, omitted
updates, restart persistence and accepted-turn snapshots are covered by unit and
isolated database tests. UI tests cover save/reset, provider changes and narrow
layouts with enlarged text. API/browser scenarios exercise saved flags through
real adapters; these fixtures do not establish live model compatibility. The comparison command defaults
to Qwen 4B with thinking off; `--compare-thinking` explicitly exercises both modes
through its test proxy using the same generation budgets.

Default-model tests verify fresh Qwen document/chat settings, preservation of
historical document snapshots and unchanged chat choices during upgrades.
The database migration test also runs the migration twice and checks that
configured context and update timestamps survive. API and Flutter tests cover
the same new-install defaults. Live property, invoice and chat tests use
`qwen3.5:4b`, including the legacy combined invoice path. These synthetic cases
exercise the default model without promising accuracy for every real document.

Issue 27 is covered by the normal unit, PostgreSQL integration, API E2E and
browser E2E tasks. The browser harness starts an authenticated local
OpenAI-compatible fixture and supplies `LLM_FIXTURE_URL` / `LLM_FIXTURE_KEY`
to Flutter. Provider fixtures are test-only; production uses configured services.
No external API account, paid inference or Qwen download is required for these
suites. Real OCR, PostgreSQL, Temporal and generated API transport are used.
The optional `task test:llm` requires an explicit `LLM_OLLAMA_URL`, a ready Ollama
runtime and the normal embedding model initialized by `task infra:up`. It pulls
Qwen if absent and processes four synthetic invoices while requesting embeddings
from the same runtime. It verifies populated properties and usable embeddings,
without reading or modifying library documents. Missing configuration fails
clearly. The invoice adapter's live tests also verify a synthetic invoice with
multiple VAT rates in one currency and an invoice with an explicit separate VAT
accounting currency. Test packages run sequentially so these additional model
requests do not compete with the concurrent property-extraction test's deadline.
This additional live-model suite is separate from `task test:all` because
it needs the Qwen download and additional inference resources.

The default Ollama container permits up to 8 GiB and two resident models. Allow
that memory alongside PostgreSQL, Temporal and the 4 GiB processor. CUDA/ROCm
builds need matching hardware and drivers and are separate from the CPU baseline.

AI chat tool-budget regressions include two uploaded PDFs (text and scanned
pages), paginated tool discovery, thirty persisted calls followed by a final
answer, private conversation paging and deletion during inference. The browser
scenario uploads a two-page PDF, follows older conversation history, refreshes
loaded pages and confirms deletion through the UI.

For a separate live Qwen check with actual uploaded PDFs, export
`TEST_DATABASE_URL`, `DOCUMENT_PROCESSOR_URL`, `TEMPORAL_ADDRESS` and
`LLM_OLLAMA_URL`, then run from `backend`:

```sh
go test -race -count=1 -tags=e2e,llm_live -run '^TestAIChatLivePDFDiscoveryAndEvidence$' -timeout=15m -v ./tests/e2e
```

This optional test creates a disposable schema, storage and owned task queue,
uploads two synthetic bills, and checks discovery, both document reads, trusted
source IDs and the expected amounts. It logs only synthetic answers and tool
names, offsets and search terms. It requires the installed `qwen3.5:4b` model and real ingestion
services; it is distinct from the deterministic provider fixtures in the baseline.

`TestAIChatLiveExampleDocuments` additionally uploads two dated example employment
contracts and tests a greeting, a German question about the latest salary, and a
missing insurance invoice. Run it with the same environment:

```sh
go test -race -count=1 -tags=e2e,llm_live -run '^TestAIChatLiveExampleDocuments$' -timeout=20m -v ./tests/e2e
```

This optional regression logs the synthetic answers and complete tool results,
checks for repeated executions, and requires the salary answer to read and cite the
latest contract. The missing-document answer also needs manual review for a clear
statement that the amount could not be verified. These live checks can fail when
the installed model makes poor retrieval decisions; they are not baseline CI tests.

Resource scheduling tests run in the existing Go unit, isolated PostgreSQL, compiled API and browser suites. They require no additional runtime dependency. Retained-reservation, concurrent admission, FIFO feasibility and admin revision tests use random disposable schemas. The existing GitHub fast-check job automatically discovers scheduler and workload UI tests; full local verification still needs PostgreSQL/pgvector, Temporal, the document processor and Chrome as described above.

## Mobile share checks

`flutter test test/unit/mobile_share_cubit_test.dart` from `frontend/` covers
pending shares through sign-in, explicit confirmation, duplicate event delivery,
late reads after library replacement, queue capacity, permission gates, cleanup
and the iOS credential fingerprint context. These tests are included in
`task check`. `task test:e2e` covers the common UI/API/storage upload workflow.

On macOS, build the embedded extension with `task build:ios -- --simulator`.
Run its native file, image-conversion, multipart, receipt, response-limit and
identity tests with the following command from `frontend/ios/`, substituting
an installed simulator ID from `xcrun simctl list devices available`:

```sh
xcodebuild -project Runner.xcodeproj -scheme ShareExtensionTests -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  test
```

`task build:ios` also checks the unsigned device release build.
`task build:android -- --release` checks the Android receiver in the minified
release artifact. Run Flutter builds sequentially: platform generation shares
files in the frontend working directory. Full native builds require enough free
disk space for Xcode, Gradle and Flutter intermediates.

For device acceptance, use a signed iOS app with both targets provisioned for the
same Keychain group, and an Android release APK. Use a test account and library.

1. Share a PDF from Files/a file manager and one or several photos from Photos or
   a gallery. Check the share target, filenames, destination and per-file results.
   On iOS, also share HEIC and verify the orientation and converted JPEG quality.
2. Exercise cold start, an already-open app and a backgrounded app. On Android,
   receive while signed out and complete server setup/sign-in before confirming.
   Reopening the app must not replay a consumed share.
3. On iOS, confirm shared Keychain access after upgrading a signed installation
   with an existing session. Check locked-device behavior, missing login, initial
   password change, upload-only permission and denied upload permission.
4. Change library/server or sign out while a file is being prepared. No pending
   content may be sent using a replacement identity. Confirm an iOS sheet's
   displayed destination against the library where the original was accepted.
5. Try cloud-backed files, revoked URI grants, empty files, unsupported data,
   21 files, a file above 100 MiB, and an Android batch above 200 MiB. No rejected
   Android batch may partly upload. A second Android share must preserve the first.
6. Test cancellation before sending and during transfer, duplicate files, loss of
   network, HTTP LAN access, trusted HTTPS and rejected certificates. Verify that
   uncertainty asks users to check the library and never triggers an automatic
   retry. iOS must not follow a redirect with the authenticated upload.
7. Inspect temporary-file cleanup after success, discard, session replacement
   and process restart. Neither platform adds a broad storage permission or stores
   bearer tokens in its file cache.

OS share-sheet discovery, URI grants, phone provisioning and extension termination
cannot be established by browser tests or unsigned compilation. Report which
platforms and device scenarios were actually exercised in the PR.
