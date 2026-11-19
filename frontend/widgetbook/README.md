# Domabas Glacier catalog

Widgetbook hosts reusable Flutter components, desktop and mobile screens, and
native desktop frame previews.
It imports the real presenters from `frontend/lib/ui/`; fictional records and
interactive scenario state stay in this development app. No account, API,
database or cloud service is required.

Use the repository's pinned Flutter SDK and run from the repository root:

```sh
task widgetbook
task widgetbook:check
task widgetbook:build
```

The local web server uses `http://127.0.0.1:7358`. The release output is
`frontend/widgetbook/build/web`. Building does not publish it. The main
application continues to support all six Flutter platforms independently.

Choose an example from the sidebar. The addons offer light/dark themes,
desktop/laptop/short/compact viewports, text scaling and reduced motion. A
component example uses `CatalogFrame` when it needs a scrolling, bounded canvas;
a complete screen supplies its own full-height layout.

## Adding examples

Add cases to `lib/catalog/<domain>_cases.dart` and register their list in
`catalog.dart`. Each `CatalogCase` has a unique stable kebab-case `id`, a domain,
component, state name, actual `widgetType`, and a normal Flutter builder. The
builder must run without Widgetbook-specific inherited state so it can be tested
directly. Use local stateful fixture widgets for interaction and dispose their
controllers. Production presenters never import this package.

Use meaningful states: loading, empty, failed/retry, disabled/read-only, long
content, partial results and edit recovery where relevant. Full screens compose
the same presenters shown individually. Do not initialize the production app or
replace its repositories with catalog fixtures.

`?case=<id>` opens a full-window example without host chrome for review. Optional
query parameters are `appearance=dark`, `textScale=2`, `motion=reduced` and
`opaque=true`.
The regular catalog remains the default route.

Open the complete workload settings screen in the
[desktop workspace](http://127.0.0.1:7358/?case=desktop-admin-inline) or the
[phone workspace](http://127.0.0.1:7358/?case=mobile-workload-ready). Select
a pipeline to see its resource usage. Move the ingestion slider to change the
sample load, or edit and save a limit to see the diagram reflect the new capacity.

The catalog test checks unique identities and renders every registered case in
both themes at wide, short and compact sizes, plus enlarged text. These checks
detect Flutter exceptions and layout overflow; they supplement visual and
interaction review and do not certify native builds or backend functionality.

Widgetbook is pinned exactly and this package has its own committed lockfile.
No generator or cloud integration is installed. Update versions deliberately,
resolve the lockfile, and rerun analysis, tests and the web build.

## Dependency notices

The catalog home links to its own Flutter license page. The web build bundles
the dependency notices collected by Flutter, including Widgetbook, and the
local DM Sans and Barlow Condensed font notices. This page describes this
development artifact's dependencies. The production app's separately generated
license inventory remains scoped to its runtime and repository tooling; adding
this catalog does not add Widgetbook to the production app dependency graph.

The repository license generator fingerprints all package manifests and locks,
including this development host. After intentionally changing them, refresh the
canonical inventory through `task generate:licenses -- --collect` and rerun its
check. This records the changed inputs without mislabeling host-only dependencies
as production client dependencies.

## Coverage

The [coverage contract](COVERAGE.md) maps the current desktop product families to
catalog cases and lists every public Glacier widget. The source/registry test
fails when a new public presenter has no named example.

## Native frame previews

Native cases use `native-<platform>-<state>` IDs and supply their own explicit
macOS, Windows or Linux theme context, window mode, appearance and text scale.
Use `test/fixtures/glacier_native_reference.json` for each case's exact viewport
size. For example, `?case=native-windows-reader` opens the desktop reader inside
the Windows frame; `?case=native-compact-navigation-open` demonstrates the
compact drawer. Add `preview=true` to expose the Window preview control, which publishes local
simulated state.

Six original contract cases, an isolated titlebar and three inherited-context
examples cover all eight public native widgets and the shared workspace geometry. Caption commands, drag-region reports and focus behavior
are testable in the browser; real window movement, system hit testing, host
menus and OS accessibility require the appropriate native host. These examples
do not initialize or replace production runners or native services.
