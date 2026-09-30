# Repository scripts

Use the root [Taskfile](../Taskfile.yml) for everyday commands. These folders
contain the Bun TypeScript implementations and their tests.

| Folder | Purpose | Task entry points |
| --- | --- | --- |
| [ci](ci/) | CI suites, runner setup, Flutter installation and Docker networking | `task ci`, `task ci:setup`, `task ci:flutter`, `task ci:database` |
| [development](development/) | Local app builds, development, Compose, PostgreSQL and native Ollama | `task build:app`, `task build:android`, `task build:ios`, `task build:macos`, `task build:windows`, `task dev`, `task infra:up`, `task compose:up`, `task db:up` |
| [diagnostics](diagnostics/) | Memory reports and AI model comparisons | `task diagnose:memory`, `task evaluate:ai` |
| [generation](generation/) | API clients, database adapters, icons, license inventories and generated-code checks | `task generate`, `task generate:db`, `task generate:icons`, `task generate:licenses` |
| [release](release/) | Version selection, image publication and GitHub releases | `task release` |
| [security](security/) | OSV dependency scans and Trivy image scans | `task security:dependencies`, `task security:image` |
| [shared](shared/) | Process ownership, cancellation, environment loading and repository paths | Imported by other scripts |
| [testing](testing/) | Database, browser E2E and Compose test harnesses, workflow cleanup and cross-tool tests | `task test:integration`, `task test:temporal`, `task test:api-e2e`, `task test:e2e`, `task test:compose` |
| [testing/browser](testing/browser/) | Pinned browser installation and focused Flutter browser suites | `task test:browser`, `task test:scanner:web`, `task test:realtime:web`, `task test:documents:web`, `task test:uploads:web` |
| [testing/fixtures](testing/fixtures/) | Local email, LLM and Paperless fixture servers, plus sample documents | Used by test harnesses and Flutter tests |

Keep each `*.test.ts` next to the implementation it exercises. `task lint:scripts`
and `task test:scripts` cover every subfolder. Put new scripts in the matching
folder and add public commands to the Taskfile.

Direct invocation uses `bun --no-env-file scripts/<folder>/<name>.ts`. Shared
helpers resolve the repository root from [shared/runtime.ts](shared/runtime.ts),
independently of the caller's working directory. Follow the
[development guide](../docs/development/index.md#monorepo-tooling) and
[tooling architecture](../docs/arch/tooling.md) for environment and process rules.
