# Development tooling

Go Task names the developer commands. Bun TypeScript scripts start services, generate API code, run tests and manage temporary resources. The scripts load `backend/.env` explicitly and apply exported variables afterward. Air receives only exported variables, so the Go service can read updated file defaults each time it restarts.

The [script directory map](../../scripts/README.md) groups automation into CI,
development, diagnostics, generation, release, security, shared helpers and test
tooling. Browser helpers and fixtures have their own test-tooling subfolders.
Tests remain beside the code they exercise; Bun and TypeScript discover them
recursively. All folders use `scripts/shared/runtime.ts` for repository paths and
process ownership. Task names remain the public interface.

`OLLAMA_RUNTIME` selects CPU, CUDA, ROCm or native Apple Silicon MLX for `task dev`
and `task infra:up`. Development passes explicit Compose overrides; deployment
and disposable test helpers retain their Docker baseline. MLX uses the official
checksum-pinned macOS runtime in `.cache/tools`, an owned loopback listener and
a retained `.cache/ollama` cache mounted read-only into the processor. A container
probe checks host gateway connectivity before infrastructure starts. The processor
still verifies the runtime version and pinned embedding artifacts. Model choice
determines whether Ollama uses its MLX engine; saved application choices are
preserved. No HTTP contract, stored configuration or authorization boundary changes.

The native inference process has a separate process scope. Application processes
drain before that scope closes; startup failure, native process failure and
cancellation also close the owned server. `task infra:up` keeps the native scope
in the foreground until interrupted. Docker data and both model caches survive.
The [development runtime guide](../development/compose.md#select-the-development-ollama-runtime)
describes the user-facing selector and prerequisites. The
[infrastructure tests](../../scripts/development/development-infrastructure.test.ts) cover runtime selection.

## Process ownership

The native app build helper in `scripts/development/build-app.ts` backs
`task build:app` and the Android, iOS, macOS and Windows build tasks. It checks
the host and pinned Flutter version, checks Xcode selection and SDK availability
for Apple targets, resolves the committed Dart lockfile, and builds with
`--no-pub`. It rejects lockfile changes and missing output before announcing
success. It uses the caller's environment without loading backend defaults.
Builds use the shared process scope with cancellation and a one-hour deadline;
Android disables the persistent Gradle daemon. No server, generation, signing
credential installation or publication is part of these tasks. The
[local app build guide](../development/build-apps.md) documents required setup
and the distinction between unsigned iOS, simulator and installable desktop/APK
outputs.

Each script owns the child processes it starts. On Unix, a process group includes the command and its descendants. A wrapper can exit before its service finishes, so cleanup waits for the whole group before forcing it to stop. Windows batch tools use an argument adapter that preserves Flutter's normal startup behavior.

Foreground `run` and `capture` commands clean up remaining descendants before
returning, including successful wrappers and captured nonzero exits. The scope
removes ownership only after cleanup succeeds. Captured output retains its
complete-pipe deadline, and cleanup failure cannot replace the command's original
timeout or cancellation error.

For a signal-terminated child, Bun can leave `exitCode` null even after `exited` resolves. The managed wrapper retains that resolved exit code so readiness and cleanup can observe the actual completed state. A real-process interruption test covers this case.

On macOS, a group containing only exiting processes can produce EPERM before its leader is reaped. Cleanup opens a 500 ms verification window, using `/bin/ps` snapshots that each have a one-second timeout. It accepts the result only when a successful snapshot proves the exact owned group is absent and the leader's exit is observed. Active leaders, live or unverified groups, probe failures and permission failures on other platforms still fail with PID/signal context. The [Darwin signal implementation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_sig.c#L1718) explains why an exiting group can return this result.

Linux container PID 1 may leave orphaned children as zombies. Signal zero still
finds their process group, although those children have finished executing.
After observing the leader's exit, cleanup checks a bounded `/bin/ps` snapshot
for live members of that exact group. A group containing only zombies is stopped;
live descendants retain the full drain period. An unavailable or malformed
snapshot falls back to the bounded grace period and SIGKILL. Permission errors
still fail. Containerized local CI runners can use `--init` to reap orphans.

A capture timeout covers process exit and output pipes: a descendant can keep a pipe open after its parent exits. Cleanup preserves the original operation's error and reports a separate cleanup failure. Error messages do not include full command arguments because those may contain credentials.

The Go service needs time to drain Temporal work. Air, Bun and Compose allow enough shutdown time for that drain. A test covers a parent process exiting while its child is still finishing work.

The web server resolves the Go service through Docker's DNS repeatedly, so a recreated API container can receive requests at its new address.

## Generation and downloads

Generator and browser downloads use pinned versions. The OpenAPI Generator JAR is checked against its expected checksum. Generated Dart output is prepared in a separate directory and replaces the previous output only after success; a failed replacement restores the previous directory.

The Dart package excludes the generator's unused standalone publishing script, Travis template and README with links to disabled API docs. The frontend guide documents the client; repository publishing and CI use the root tooling and GitHub workflow.

The Go and Dart generation paths remove ordinary standalone explanatory comments. They keep generated-file markers and compiler or analyzer directives. This step is limited to the syntax emitted by the pinned generators and fails if a new multiline string layout needs review. It does not change the API contract or executable statements. The OpenAPI specification and architecture files carry the explanations instead.

Database generation uses the module-pinned Jet v2.16.0 CLI and Bun's built-in SQL
client. `task generate:db` creates a random schema, applies the canonical embedded
migrations through `cmd/migrate`, and generates the explicit table allowlist in
[scripts/generation/generate-database.ts](../../scripts/generation/generate-database.ts) into a temporary directory.
That list covers selected identity, document, email, invoice, Paperless and scheduler
tables. Strict normalization checks the complete output tree,
replaces exactly one constructor schema literal in each table file with an empty schema, rejects
remaining random schema references and omits the verified global schema mutation
helper. The generated marker remains; ordinary generator comments are removed.
No generated file is edited by hand. `task generate:db:check` compares all paths
and contents without writing the committed directory. Both commands clean up
only their successfully created schema and temporary directory; cleanup uses a
fresh bounded database connection after cancelled or failed work. Connection URLs
and captured generator errors are not logged. Builds use committed outputs and
need neither live PostgreSQL nor generation. API generation and `task check`
remain database-free; full local Linux validation runs the database check after provisioning
its disposable PostgreSQL service.

Browser ZIP extraction uses a new directory, rejects escaping paths, preserves executable permissions and checks that symbolic links stay inside the extracted directory. Executable validation happens before the new browser replaces the previous one.

## Application icon generation

`task generate:icons` uses pinned Sharp 0.35.4 to export platform images and
vector resources from the canonical Filed Paper SVG. Checked-in output includes
all native sizes, web assets, and the in-app mark. `task generate:icons:check`
compares those files without writing and runs in `task check` and GitHub CI.
See [application branding](frontend/branding.md) for platform handling.

## Infrastructure and tests

Compose owns local PostgreSQL and Temporal. The administrative initializer creates separate databases and roles. The Temporal role then applies only its own schemas. The namespace initializer runs as a checked one-shot command after Temporal is healthy; Compose's wait mode expects a running service when that service is the direct target.

Temporal runs the digest-pinned official server image. Its container probe checks
the listening port; the namespace initializer waits for real gRPC cluster health
before registration, and backend readiness continues checking Temporal and its
namespace. Empty dynamic overrides use `/dev/null`. Test cleanup runs the CLI
from the existing initializer image, so no custom Temporal server image is needed.

The browser test harness uses a unique database schema and Temporal queue. PostgreSQL clients receive the connection URL explicitly through `--dbname`. Cleanup uses a fresh process scope so cancellation cannot prevent removal of the test schema. Full local checks and Compose smoke tests generate their own project names and remove only those disposable projects and volumes.

Full browser E2E uses Chrome's temporary-directory shared-memory fallback so
Docker's default 64 MiB shared-memory mount cannot prevent Dart modules from
loading. Chrome console messages stream into the test log with fixture secrets
redacted. Polling is bounded and stops with the owned test process; diagnostics
do not change the test result or its ten-minute deadline.

Scanner and realtime browser unit checks reuse the pinned browser installer and
managed process scope without starting a backend. Both run in the full Linux
check harness and `task test:all`; an explicit `CHROME_EXECUTABLE` can select a local browser for
diagnosis without changing the repository's pin.

Tooling tests have a 30-second deadline, including process shutdown headroom.
Process fixtures signal readiness before their parent exits or sends a signal.
Foreground commands can set a process deadline. Expiry stops the owned process
group, preserves the timeout error and lets the enclosing harness clean its
infrastructure. Focused Chrome suites use three-minute deadlines and expanded live progress.
The combined local run registers all browser groups in one entry point with a
six-minute deadline, avoiding repeated compiler and browser suite startup. Bun CLI
deadlines bound CI checks, Compose smoke and release work even on older runners
that ignore YAML job timeouts;
PR concurrency groups cancel obsolete commits without cancelling main releases.
GitHub Actions runs `task check` and isolated PostgreSQL integration/database
regeneration on PRs and main pushes. It uses GitHub-hosted Ubuntu runners. Full
Temporal, browser, API E2E, model and Compose checks remain explicit local tasks.
The local full harness retains Docker gateway discovery and unique projects.

Main pushes also run checksum-pinned OSV-Scanner against Go, Dart and Bun inputs.
The TypeScript adapter renders all findings and blocks only critical ratings;
scanner failures also fail the job. Source scanning does not cover image OS or
native library vulnerabilities.

The serialized release job uses GitHub's `queue: max` to retain pending merges.
The publisher lists every page of tags and releases, reserves a semantic version
as a lightweight tag at the exact event commit, and creates a draft. PR labels
select minor or major; patch is the default. Reserved tags survive interrupted
builds. Retrying the same commit reuses its version; moved/deleted tags or
ambiguous versions fail. Published retries do no writes or builds.

Docker Buildx builds and loads backend, web, document-processor and init images
into the runner's Docker engine. Trivy scans each immutable local image ID, and
its report must identify that same image. Only after all four critical-only gates
pass does the publisher push the scanned images to GHCR, without rebuilding.
The publisher checks local tag identities again before each push. All target
Linux AMD64; the web image contains the Flutter web build.
No native applications are published. The job token receives repository and
package write access only in the main-push job. Docker credentials are scoped
to that runner's configuration, restored on exit and excluded from build process
environments. OCI labels record source, revision, version and the project license.
The images retain the third-party license catalog.

Only after all four images return digests does the publisher finish the release.
Notes include pull commands and a Compose configuration with digest references.
Build or scan failures prevent every image push. Publication still spans separate
registry/API writes, so a later registry failure can leave partial scanned image
tags. Draft retries may replace those images; published versions
are not rebuilt. There is no floating latest tag. Version reservations can leave
gaps, and queue arrival can differ from commit order. Versions below 1.0.0 are
GitHub prereleases, reflecting preview status.

The Trivy runner verifies its pinned archive, uses vulnerability-only scanning
and an explicit empty ignore file, includes unfixed findings and keeps all
severities in JSON reports. Only Trivy CRITICAL ratings block publication; scanner
errors also fail. Reports are retained for 14 days even on failure. Database
caching preserves normal freshness checks; no database update is skipped. The
image gate complements OSV but does not fully inventory custom static OCR or
compiled Dart code.

For commands and runner setup, see the [development guide](../development/index.md),
[test guide](../development/testing.md) and [release guide](../development/releases.md).

## Third-party license inventory

`task generate:licenses` builds the offline app asset and dependency index from
retained evidence. `-- --collect` refreshes that evidence from locked package
caches and explicit upstream sources. `task generate:licenses:check` runs in
`task check` and CI without network access; it detects changed dependency inputs,
missing locked entries, altered notice text and stale generated output. See the
[inventory workflow](../../third_party/README.md#complete-inventory-and-app-screen)
and [license reader](frontend/licenses.md). The audit includes development tools
and optional-platform packages, with commercial review gaps documented separately.
The release entry point runs the same check before building or publishing. Each
project image retains the root MIT license and full notice catalog in its final
stage; [artifact verification](../../third_party/README.md#artifact-notices) explains
the paths and checks for independently distributed packages.
