# Domabas contributor instructions

## Start here

Domabas is a document library with a Flutter client, a Go API with embedded
Temporal workers, PostgreSQL, a private document processor and Ollama. Read the
files below before choosing where a change belongs. The README is for people
evaluating or hosting the app; this file is the working guide for coding agents.

| Need | Source of truth |
| --- | --- |
| Product and hosting overview | [README](readme.md) |
| Components and central mechanisms | [Architecture overview](architecture.md) |
| Detailed design and pattern map | [Architecture index](docs/arch/index.md) |
| Backend layers, ownership and wiring | [Backend index](docs/arch/backend/index.md), [domain structure](docs/arch/backend/domain-structure.md), [dependency injection](docs/arch/backend/dependency-injection.md) |
| Frontend state, transport and lifetime | [Frontend index](docs/arch/frontend/index.md), [UI components](docs/arch/frontend/components.md), [identity lifetime](docs/arch/frontend/identity.md) |
| Public API | [OpenAPI contract](contracts/backend/openapi.yaml) |
| Local setup and configuration | [Development guide](docs/development/index.md), [backend README](backend/README.md), [frontend README](frontend/README.md) |
| Containers and runtime resources | [Compose guide](docs/development/compose.md), [resource guide](docs/development/resources.md), [Compose definition](compose.yaml) |
| Checks and runner requirements | [Testing guide](docs/development/testing.md), [Taskfile](Taskfile.yml), [GitHub workflow](.github/workflows/ci.yml) |
| Development plans and research | Local working notes in `docs/plans/` (ignored by Git) |

## Setup and daily commands

Run commands from the repository root unless a guide says otherwise. Use the
committed versions in [.tool-versions](.tool-versions), [.bun-version](.bun-version),
[backend/go.mod](backend/go.mod) and [frontend/pubspec.lock](frontend/pubspec.lock).
Install Go Task, Docker with Compose v2, Go, Flutter and Bun. Java 17+ is needed
for Dart client regeneration, including `task check`; native targets need their
platform toolchains. Do not upgrade dependencies as part of unrelated work.

```sh
task setup
task doctor
task dev
```

`task dev` starts infrastructure, Go hot reload and Flutter web development.
Open `http://127.0.0.1:7357`; the API defaults to port 8080 and Temporal UI to
8233. Press `r` for Flutter reload, `R` for restart, or `q` to stop the apps.
Infrastructure remains running. `task infra:down` stops it while retaining data.

| Work | Command |
| --- | --- |
| List available tasks | `task --list` |
| Start only infrastructure | `task infra:up` |
| Use already running infrastructure | `task dev -- --external-services` |
| Run a native Flutter target | `task dev -- --device <device-id>` (list with `flutter devices`) |
| Build and start the web deployment | `docker compose up --build --wait` |
| Stop the web deployment, retaining volumes | `docker compose down` |
| Regenerate the public API adapters | `task generate` |
| Apply pending application migrations | `task db:migrate` |
| Regenerate database adapters after a schema change | `task generate:db` |
| Format handwritten application code | `task format` |
| Run the standard local check | `task check` |

The checked-in `backend/.env` holds development defaults. Read it only as needed;
preserve existing local edits and do not copy deployment secrets into docs, logs
or commits. Exported settings override defaults. The Go process also supports
`DOMABAS_ENV_FILE`; tooling still loads its documented defaults explicitly.
See the [configuration guide](docs/development/index.md#configuration) before
changing database ports, API origins, model runtimes or external services.

## Change workflow and validation

1. Inspect `git status` and preserve unrelated user changes. Read the relevant
   architecture guide and implementation before editing.
2. For substantial work, record plan, research, critical review and revised plan
   locally in `docs/plans/` before implementation. These are development working
   notes; never stage or commit them. No published plan index is required.
3. Change the canonical source first: OpenAPI for HTTP changes, a new immutable
   SQL migration for database changes, and the canonical SVG for branding.
   Run the matching generator and commit generated outputs and deliberate locks.
4. Keep topic guides and indexes current. Write README text for humans. Keep
   working decisions and validation notes in the local plan. Report checks run
   for the change in the task or PR report. Keep tracked documentation focused on
   current behavior, prerequisites, required checks and support limits; do not
   add workstation histories, past test reports or test logs. Record lasting
   decisions in the appropriate topic guide. Do not link tracked documentation
   to local plans.
5. Review the diff, run the checks below that apply, and report unavailable checks
   with their reason. Do not claim another host's native build passed.

| Change | Required validation |
| --- | --- |
| Application code or shared behavior | `task check` |
| TypeScript tooling | `task lint:scripts` and `task test:scripts` |
| Database persistence or migrations | `task test:integration`; `task generate:db:check` when generated tables change |
| Public API behavior | `task test:api-e2e` |
| Temporal execution or worker lifetime | `task test:temporal` |
| UI/API/storage workflow | `task test:e2e` |
| Complete Compose deployment | `task test:compose` |
| Full baseline | `task test:all` (Compose smoke and live-model tests are separate) |
| Documentation only | Check linked files and headings, indexes, commands against Taskfile, diagrams and screenshot contents; `git diff --check` |

Database and browser test harnesses use disposable schemas and matching unique
queues. Use those harnesses; never truncate development tables or delete retained
volumes. `task check` requires no running database. The
[testing guide](docs/development/testing.md) explains external service settings,
the separate live-model suite, browser prerequisites and the CI/full-suite split.

## Mandatory rules

- MUST NOT invoke Claude or run the `claude` command without the user's explicit approval immediately beforehand.
- Read [architecture.md](architecture.md), [docs/arch/index.md](docs/arch/index.md), and the relevant backend/frontend architecture document before structural changes.
- For substantial changes, record the initial plan, current primary-source research, a critical review ("grill"), and the revised plan before implementation. Keep these development records and working validation notes locally in the Git-ignored `docs/plans/` directory; never stage or commit them. Put lasting decisions in tracked topic guides and report executed checks in the task or PR report, without adding historical test reports to the repository. Verify stable versions from official sources; pin dependencies and update lockfiles deliberately.

## Architecture

- Keep the high-level architecture overview in root `architecture.md`. Keep detailed architecture documentation under `docs/arch/`, with each topic in a separate Markdown file.
- Maintain `docs/arch/index.md` as the architecture entry point and link every architecture document from it. Each architecture subdirectory must also have an `index.md` linking its documents. Update the relevant indexes whenever documents are added, moved, or removed.
- `contracts/backend/openapi.yaml` is the canonical public HTTP contract. Change it first, then run `task generate`. Commit both generated Go server/types and Dart client. Never hand-edit generated code.
- Keep domain models independent of HTTP, SQL, generated API models, Flutter widgets, and concrete storage. Map boundary models in adapters.
- Store operational entity data in typed relational columns and child tables. Do not use JSON/JSONB payloads or SQL JSON aggregates for normal reads, writes, search, relationships or analysis. Document any immutable protocol/snapshot exception in architecture; see [the persistence decision](docs/arch/backend/persistence.md).
- Use explicit constructor injection and small repository interfaces owned by the domain that consumes them. Data sources own I/O; repositories translate persistence/transport into domain models; application services coordinate use cases; presentation handles HTTP or UI.
- In Go, use ordinary structs, pointer receivers, constructors, interfaces, and composition. Do not imitate inheritance or introduce generic repository frameworks. Propagate contexts and wrap errors with purpose. Keep wiring in `backend/internal/bootstrap` and `cmd`.
- Give handwritten types and constructors explicit domain or technology names, such as `DocumentService`, `InvoiceDataSource`, and `NewDocumentService`. Avoid bare `Service`, `DataSource`, `Repository`, `Handler`, `Container`, or generic value names that only make sense inside their folder. Name conversion helpers with `Mapper`/`mapper` and keep dedicated mapper files in `*.mapper.go` or `*_mapper.dart`. Preserve standard interface method names and generator-owned names.
- In Flutter, use immutable domain objects, instantiable data source/repository classes, and view models separate from widgets. Wire concrete implementations in `frontend/lib/app/`. Dispose clients and notifiers. Never import generated API types into domain or presentation.
- Production application paths must use the real API and PostgreSQL; test doubles belong in tests. Avoid singletons, service locators, global mutable dependencies, and persistence logic in handlers/widgets.
- Paginate every list that can grow. Use bounded API pages with usable UI continuation controls or infinite scrolling; do not hide older records behind a fixed history cutoff. Preserve pagination during background refresh.
- Group backend core code in `domain/<domain>/{models,interfaces,services}`, deterministic workflows in `domain/<domain>/workflows/*.workflow.go`, data code in `data/<domain>/{models,repos,datasources}`, Temporal activities and dispatchers in `data/<domain>/temporal`, and HTTP code in `presentation/<domain>/{models,handlers,routes}`. Keep concrete containers in `bootstrap/<domain>`. Each domain routes package exports one registration function that returns its request decorator and groups together; generated routing remains the single endpoint registry.
- Cross-domain business calls use injected, consumer-owned service ports. Repository/data-source joins use the shared schema or injected consumer-owned data ports, with explicit transaction ownership. Do not import foreign concrete services, repositories, data sources, containers or presentation. Only data repositories/sources may consume foreign data value records; core remains independent of storage.
- Every new feature defines scoped claims in the identity catalog and enforces them at its entry points. Namespace owners receive all registered namespace claims by default; unknown and system claims never follow from ownership. Keep role bundles, explicit grants and system administration separate, and keep claim IDs forward-compatible in clients.
- Keep architecture boundary tests aligned with these rules; do not weaken a test just to bypass a dependency violation.

## Comments and documentation

- Write all documentation in simple, clear English.
- Inline comments are allowed only when a complex function needs an explanation of reasoning that clear naming and structure cannot convey. Otherwise, do not add inline comments to code. Never use comments to restate what the code does.
- Put general explanations and design documentation in Markdown documentation files, following the architecture location and index rules above.

## Configuration and workflow

- `backend/.env` is intentionally checked in with local development credentials. Exported variables override it. Never replace these defaults with real deployment secrets; use environment injection or ignored local files for those.
- Keep all six Flutter platforms: Android, iOS, web, Linux, macOS, Windows. Native builds require their own host/toolchain; do not claim unexecuted builds passed.
- `task dev` starts Compose infrastructure plus native Go/Flutter hot reload. `task infra:down` stops infrastructure and `task db:down` stops only PostgreSQL; both retain data. Never delete a development database volume or local cluster as routine troubleshooting. Test harnesses may remove only their own explicitly disposable, randomly named Compose projects and volumes.
- Temporal is the queue system. Its worker runs inside the Go service. Within `domain`, only workflow packages may import the SDK's `workflow` and `temporal` packages. Other SDK/API use belongs in Temporal data adapters and bootstrap. Core models, interfaces and services remain independent of workflows and infrastructure. Workflows perform deterministic orchestration; activities perform I/O through injected ports. Keep worker lifetime separate from startup deadlines. Coordinate shutdown so activities drain before the Temporal client and database close. Preserve explicit registered names, payload fields and command order when moving or renaming workflows. Do not promise post-commit jobs through an uncoordinated database/Temporal dual write; introduce a transactional outbox when that feature is needed.
- Isolate test workers with a unique task queue for each database schema. Bound workflow executions and clean up only workflows owned by the test. Readiness must account for PostgreSQL, Temporal, the namespace, and worker health.
- Keep `docker compose up --build --wait` usable with Docker alone. The distributable web build resolves its API from the browser origin; native/local overrides remain supported. Schema and namespace initialization must work on retained volumes. Ordinary Compose shutdown preserves volumes.
- Keep scripts cross-platform when practical. Generated artifacts and dependency locks must make a clean checkout buildable without generation first.
- Implement all repository-owned monorepo automation in TypeScript executed with Bun. Keep Go Task as the command entry point; do not introduce Python helpers. Pin Bun and tooling dependencies, commit `bun.lock`, and use `bun install --frozen-lockfile` in CI. Keep backend/frontend application runtimes Go/Flutter.
- Disable Bun's implicit dotenv loading for tooling. Load local defaults explicitly and preserve exported overrides; pass only ambient overrides to Air so backend configuration can be reread on restart. Manage subprocess trees, cancellation, and cleanup explicitly. Run `task lint:scripts` and `task test:scripts` for tooling changes.
- Before delivery, run checks appropriate to the change. `task check` covers analysis, regeneration consistency, and fast tests. Database changes require `task test:integration`; API behavior requires `task test:api-e2e`; workflows spanning UI/API/storage require `task test:e2e`. `task test:all` runs the full baseline suite.
- PostgreSQL integration and E2E tests must use unique disposable schemas and clean them up. Never truncate development tables. Tagged tests must fail clearly when their required database configuration is missing.
- Maintain `.github/workflows/ci.yml` and document runner prerequisites. Report which checks were actually run, which were unavailable, and why.
- Use Playwright MCP for browser inspection and UI automation. Do not use Codex browser tools.
