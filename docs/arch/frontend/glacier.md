# Glacier components and screen library

Glacier is the frosted-glass Domabas design direction. The reusable Flutter
presenters live under `frontend/lib/ui/glacier/` and are exported by
`ui/glacier.dart` and `ui/domabas_ui.dart`. The isolated Widgetbook host lives in
`frontend/widgetbook/`. Production app and feature screens compose these presenters around their existing
Cubits, controllers and repository callbacks. Catalog coverage describes presenter
capabilities separately from real API workflow validation; catalog fixtures never
enter application routes.

## Ownership

Presenters accept immutable display values, child widgets and callbacks. They
never load documents, authorize actions, submit requests, persist preferences or
create sessions. Feature owners retain controllers, validation, request state,
pagination, drafts, authorization and resource disposal. The UI boundary permits
Flutter, `dart:ui` rendering primitives and other shared UI files only.

The host imports these exact presenters. Fictional records and local interaction
state belong in the host, not production `lib/ui`. No Widgetbook dependency is
added to the production package. The host does not contact the Domabas backend or
require a Widgetbook Cloud account. Original viewers are supplied as children;
PDF rendering, selection, search and binary transport stay in the existing
feature-owned viewer/adapter integration.

## Foundations

Use `GlacierTheme.light()` and `GlacierTheme.dark()` around the new compositions.
Both use the existing bundled DM Sans font. `opaque: true` replaces translucent
surfaces with solid material and removes the ambient activity pattern.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#DCE8EA` | `#0C1720` |
| Solid surface | `#F7FAF9` | `#162B35` |
| Main glass | `#F4FAF9` at 66% | `#182F3B` at 72% |
| Content surface | White at 87% | `#132831` at 92% |
| Glass edge | White at 70% | `#BADFED` at 19% |
| Document preview | `#E8EEEC` | `#1E333C` |
| Primary text | `#172C34` | `#E7F2F4` |
| Supporting text | `#53676D` | `#B8CCD4` |
| Accent | `#176961` | `#8AD5C9` |
| Accent container | `#DFEDE9` | `#1E3C42` |
| Selected navigation | `#1F434B` / white text | `#B2DFD7` / `#122F35` text |

`GlacierTokens` is a theme extension for material roles. Semantic status colors
also feed the existing `AppSemanticColors`, so notices and progress retain one
vocabulary. Body text is 14px, supporting text 12px and functional section labels
14–16px. Natural text scaling remains enabled. Use 8/12/16/24px grouping space,
10px control corners, 15px document cards, 17px toolbars and 20px sidebar/dialogs.
Desktop controls use 36–40px targets, with 44–48px controls in forms and dialogs.
Keep compact tags at 11px with 6px horizontal padding rather than Material chip sizing.

`GlacierSurface` clips its bounded 28px backdrop blur and draws the edge highlight.
`surface: true` uses the denser content material; `blur: false` avoids repeated
backdrop work on collections. Glass relies on the ambient canvas remaining visible;
nested feature Scaffolds must be transparent. The atmosphere uses broad soft teal,
lilac and slate fields behind the entire workspace. Use glass for the navigation,
floating controls and dialogs; source pages stay opaque and faithful to their
original colors. Avoid stacking many blurred surfaces or recoloring originals.
`GlacierActivityBackdrop` accepts bounded normalized caller-supplied values and
renders an abstract line or day pattern. It never fetches or invents statistics;
production aggregate availability remains a separate API decision.

`showGlacierDialog` retains the workspace under a dimmed, 6px-blurred barrier.
Search, reader, appearance, library selection and record editors use bounded modal
routes. Account management remains a permission-derived settings destination.
`createGlacierDialogRoute` and `glacierDialogBackdrop` let feature owners retain
the exact route needed for dirty-state guards, scope disposal and late-result
fencing. Routes inherit the current application theme so an open dialog follows system or user appearance changes without replacing its draft or controller. Protected forms may disable barrier dismissal. Restore focus to the
surviving trigger on dismissal.

## Component families

| Family | Public compositions |
| --- | --- |
| Foundation | Buttons, named icon actions, rich choices, switches, fields, removable tags, glass surfaces, sections, toolbar, bounded dialogs, empty states |
| Workspace | Animated collapsible sidebar, inline destination groups, sidebar Search, utilities and account context, floating quick controls, compact drawer, activity dock |
| Documents | Card/row/collection, property grid/form, related links, upload queue/receipts, reader, PDF toolbar, compact Find, original states, extracted text |
| Search | Input-first search dialog, filter groups, applied criteria and bounded vocabulary picker |
| Invoices | Exact-amount rows, detail sections, bounded record groups and complete detail composition |
| Jobs and activity | Job rows/history/details/outcomes, one pipeline timeline, reindex outcomes and grouped activity |
| Conversations | History, selectable messages and trusted source actions, controlled composer, responsive chat screen |
| Identity/settings | Settings page/records, responsive fields, identity scope, permission groups/member editor, invitation code, credentials, auth/recovery/password/server, appearance, model/email/workload, licenses/account |
| Existing presenters | Notices, status, pagination, refresh, progress and model-context controls remain reused under the Glacier theme |

The catalog groups component variants and composed screens by these domains.
Keep a distinct typed example for every public Glacier widget and named examples
for current desktop screen families. Tests compare registered widget owners
against the public source inventory; a generic visual sample is not a substitute
for a missing component contract.

## Interaction patterns

Document cards use a 1px accent edge on hover. Rich choices and switch rows use
a softer selected edge (55% accent over the solid surface); hover strengthens it
to the full accent. Disabled controls keep their muted treatment without hover
feedback. Ordinary button and sidebar hover remains a fill change.

Keyboard focus uses a 2px accent outline separated from the control by 3px
(2px in dialogs). Sidebar Search and inline child destinations keep their outline
inside the control. Pointer selection does not display this keyboard outline.
Each action owns its outline: focusing a document's Retry action does not also
outline the document opener. These paint changes preserve layout and existing
focus and accessibility actions.

The internal interaction painter observes Flutter pointer and keyboard events.
On web, a conditional SDK-only adapter under `ui/platform/` also observes
capture-phase browser pointer-down events: Flutter's accessibility DOM can
activate controls without forwarding those events through Flutter's pointer
router. The adapter observes input origin only, creates no DOM or service, and
removes its exact listener when the owning widget is disposed. Semantic
activation alone never changes input modality, so assistive actions retain
keyboard focus treatment. The native stub adds no browser dependency. Structural
checks permit JavaScript interop only for this named rendering-input adapter.

The selected sidebar destination identifies the page. Do not repeat its headline
above each collection. Record details, setup forms and dialogs retain accessible
names and contextual titles. Search sits below Domabas and opens with Cmd/Ctrl+K.
Only common quick filters belong in the floating collection toolbar. Library,
Activity and Appearance share one icon row with tooltips; all three disappear
from focus/semantics when the sidebar is collapsed. Account controls provide the
compact utility route.

User settings and Admin settings are inline expandable sidebar groups. A parent
click toggles its children without navigating or changing the selected leaf.
The caller supplies permission-filtered `GlacierDestination.children` and the
actual selected leaf ID. Groups expand independently in one top-anchored,
scrollable navigation list. A selected leaf reveals its group initially and
when selection changes; unrelated rebuilds respect manual collapse. Group
expansion animates the child list height and chevron without a flyout or an
upward jump of the parent. Hidden children immediately leave pointer handling,
focus traversal and semantics, then unmount when the closing animation finishes.
Reduced motion removes spatial transitions. Enter/Space toggles; Right opens
or focuses the first child; Left/Escape closes and returns focus to the parent.
Activating a group in the collapsed rail expands the sidebar. Compact drawers
use the same inline navigation. Expansion scrolls the selected or first child
into the navigation viewport when needed, without moving keyboard focus.
Resizing into compact mode does not open the drawer automatically. Sidebar
collapse still folds the utility row.

Optional settings overviews remain available to mobile More and contextual back
navigation. The caller supplies `GlacierSettingsDestination` values and handles
navigation; `GlacierSettingsOverview` owns no permissions or application state.
Its natural-height rows preserve descriptions at narrow widths and enlarged
type. `GlacierSettingsHeader` identifies the leaf and its optional overview
return route. It is neutral content that composes into the floating toolbar.

`GlacierSettingsSection` groups related settings in an edged, readable Glacier
surface. Put one card around a coherent task, not around each field. Existing
`AppSurface(glacier: true)` containers already supply that surface and must not
be wrapped again. `GlacierSettingsPage` supplies scrolling, section spacing,
feedback and action reachability; callers explicitly choose section cards.
Standalone settings records opt into `GlacierSettingsRecord(card: true)`;
records inside a chooser or another section keep the default flat treatment.
Dialogs retain their own single outer surface. Mobile settings sections share
the same card material, and form controls remain owned by their existing views.

`GlacierActivityDock` receives caller-owned `GlacierActivityJob` display values.
Its optional `GlacierActivitySummary` separates exact server totals and truthful
status from the bounded preview rows. Production combines source-specific job
evidence with upload receipts; unknown totals remain unknown and stale evidence
stays labeled. Opening Activity uses that same live owner, not a catalog snapshot.
It stays at the workspace bottom right and exposes a small stacked preview when
multiple jobs exist. Hover, focus or click opens a bounded panel upward; the
expanded panel overlays content without changing page layout. The workspace
keeps its full viewport. `GlacierWorkspaceGeometry` supplies measured trailing
scroll extent for the visible token and expanded panel, including their gap and
bottom clearance. Pages append a spacer after their final actions; they do not
reserve a separate bottom band. Pagination, settings actions and chat controls
remain in scrollable content so end-scrolling brings them above the overlay.
Final action blocks report their real height, including subsequent content but
excluding the clearance spacer. The panel preserves an action lane of the larger
of that measurement or 64 scaled pixels, plus 16px. Inline details require at
least 196 scaled pixels after that lane. When they cannot fit, click or Enter
opens the existing Activity dialog; hover and focus leave the token compact.
Resizing an open panel below that limit closes it and restores token focus when
needed, without opening a dialog. Action measurements reset on page changes.
Zero jobs hide it unless a refresh
error needs an action. Stale, unknown, failed, partially completed and completed
states retain their explicit labels. Progress appears only when the caller
supplies a recorded fraction. Truncated lists disclose that additional activity
may exist and retain the full activity route. No widget fetches data or creates
completion estimates. Narrow or short windows use a compact activity action.

Search criteria are drafts. Enter applies query and filters together; Escape
clears the draft before dismissing an already-empty dialog. IME composition must
not submit prematurely. Quick filters apply immediately. The feature owner
preserves applied criteria, sort, loaded pages and scroll position across refresh.

`GlacierPreviewPlaceholder` fills an existing bounded preview slot while a PNG
preview is being prepared, transferred or decoded. It paints a quiet document
silhouette with a clipped shimmer using Glacier preview colors. Metadata,
selection, actions and preview overlays stay in place. The feature owner chooses
this presenter from actual pending state; absent, unsupported and failed previews
retain their distinct fallback or retry treatment. A ready image takes priority.
Reduced motion uses a static silhouette. TickerMode and inactive application
lifecycle suspend the animation. Cached previews outside their scroll viewport
also pause and resume when revealed; only the preview repaint boundary changes.
The placeholder exposes one stable preparation label, with no fabricated progress
or repeating announcements, and owns no API calls or retries.

Preview failures use `GlacierPreviewRetry` inside the document item. Cards expose
`onRetryPreview` and place its compact Preview action within the existing image
area, beneath the top status and selection lane. Rows and enlarged-type mobile
cards use an icon action with the same accessible name. The retry is a sibling
of the main opener, outside its excluded preview semantics, so keyboard and
assistive actions remain independent.
Preview and processing retries keep distinct callbacks and accessible names even
when both fail. A preview error does not add a footer, enlarge the card or replace
the processing action. The caller supplies a retry callback only for a genuine,
retryable preview failure; pending, ready and absent previews hide it.

Rich choices retain checked, mixed, disabled and keyboard semantics. Inherited
permissions remain visibly selected and non-editable; explicit grants remain
separate. Credential fields distinguish retained secrets, replacements and
removal. They never display a stored secret received from an API.

The reader keeps Edit, Resync, Download and Delete above the scrollable content.
Original/Text switches the canvas; properties, related documents and processing
remain directly in the inspector. PDF page/zoom controls stay compact. Find is
an on-demand overlay with count, previous/next and close; Escape dismisses Find
before the reader. Feature adapters supply real PDF search results and original
viewers. Scope and confirmation remain explicit for deletion and reprocessing.

Jobs show recorded evidence. Unknown stages are not complete; queued downstream
work is not processed. All five pipeline families use the same timeline presenter.
Activity stays independent of job-history filters. Reindex totals can be unknown;
finished failures, skipped and superseded items remain distinguishable.

Forms keep drafts through errors and conflicts. Distinguish saving, saved,
rejected, changed elsewhere and unknown outcomes. A retry after uncertain receipt
must reconcile the same operation before submitting new work. Never infer invoice
payment/approval from extracted fields or add different currencies together.

## Responsive behavior and checks

Layouts use available width, not the operating system. The production workspace
uses the mobile shell below 800px and the desktop shell from 800px. Desktop uses
a 224px sidebar or its 76px collapsed rail; the standalone native presenter also
supports a compact drawer. At wide desktop sizes,
use 24px outer horizontal margins, 16px vertical margins, 20px shell gap and
20px content insets. The floating quick-filter toolbar fills the workspace width. Animated collapse is bounded;
reduced motion removes that transition. Feature compositions stack details and
forms as width or text scale requires. Headers/actions stay bounded and scroll
separately when short windows or enlarged text need more room.

The mobile shell uses a 70px tablet rail from 600px available width. When
the scaled 15px reference text exceeds 22px, the rail becomes 208px with
horizontal icon/label rows and a 232px content offset. The rail scrolls and
reveals the selected destination. Enlarged mobile headers put their controls
in a 48px row, followed by an 8px gap and a full-width title and scope.
`GlacierMobileFieldGroup` pairs explicitly related fields only when its local
width is at least 492px and the same text-scale threshold is not exceeded.
Its 12px gutter preserves at least 240px per field; narrow and enlarged layouts
stack in the same reading and focus order.

Appearance and search choices expose one selected, named action per option.
Merge selection semantics with a button's own action rather than nesting
another button role. Exclusive choices expose checked state in a mutually
exclusive group; independent choices expose checked state individually.
Reserve toggled semantics for switches. Disabled selected values remain readable while their
interaction stays disabled. Catalog library selection and accepted scan counts
belong to the preview session; production feature adapters provide the real
identity scope, document metadata and callbacks.

Catalog tests render examples in both themes at wide desktop, 800×600 and 390px
fallback sizes, plus enlarged text. Focused tests cover callback behavior and
recovery/selection semantics. Use Playwright MCP to inspect a served web build;
Dart source is not covered by the Impeccable HTML/CSS detector. Native toolchain
builds and assistive-technology conformance require their own verification.

From the repository root:

```sh
task widgetbook:setup
task widgetbook
task widgetbook:check
task widgetbook:build
```

`task check` includes the catalog check. CI also builds the catalog web app.
See the [catalog README](../../../frontend/widgetbook/README.md) for direct
preview URLs and adding cases, and [testing](../../development/testing.md) for
repository-wide validation requirements.

## Native desktop presentation

`GlacierNativeFrame` composes the accepted desktop workspace with explicit
macOS, Windows or Linux window state. Immutable window values and layout
reports use logical coordinates. Command callbacks report intent; the caller
publishes acknowledged mode changes. The native host owns actual window APIs,
physical-pixel conversion, system-menu events and platform decorations.

`GlacierNativeTitleBar` is a dedicated, full-width glass bar with window title,
library context and platform controls. It is 44px high normally and 52px with
enlarged text in every mode. Identity stays on one ellipsized line with its full
accessible name. Fullscreen Exit stays on the same row, using a named 44px icon
action when compact or enlarged. Caption hit regions retain their full height. The sidebar and quick-filter toolbar begin 16px below the bar;
caption reservations never shorten those content controls. The frame keeps
this bar outside the nested application Navigator. Application dialogs use
that local Navigator and clip their blur and scrim below the measured bar. Compact navigation begins at 760px, keeps its drawer
and scrim in one layer, and excludes background application controls from focus
and semantics. Native caption controls remain reachable while app overlays are
open. Fullscreen exit and maximize/restore retain equivalent visible focus.

`GlacierNativePresentationScope` supplies the measured titlebar height and
overlay state. `GlacierNativeContentInsets` remains an explicit host content-inset
context; the dedicated-bar composition supplies zero side reservations. The production [desktop host](platforms.md#glacier-desktop-window-integration) connects these presenters to acknowledged platform commands. Browser and mobile compositions retain their own defaults; the presenter library itself performs no operating-system calls.

The platform contracts remain explicit:

| Platform | Caption and reservation contract |
| --- | --- |
| macOS | Glacier draws the title and leading traffic lights throughout the window lifetime. AppKit handles their commands and native dragging. |
| Windows | Trailing minimize, maximize/restore and close controls; measured interactive exclusions take precedence over draggable space. |
| Linux | Caller-selected standard, close-only or leading control layout; host decoration mode removes client captions. |

Restored, maximized and fullscreen are separate states. Inactive and unsupported
controls retain their geometry. Both command capability and a supplied callback
are required for activation. Layout reports defensively copy their collections,
use the dedicated bar as the drag candidate, exclude caption/control rectangles
and resize edges, and refresh after layout,
sidebar animation and overlays. They are hints for a native adapter, not an
implementation of platform non-client hit testing. Reduced motion and opaque
material settings retain all controls and interaction ownership.

Material selection stays with the enclosing app theme. When the native state
carries an opaque preference, supply the matching
`GlacierTheme.light(opaque: state.opaque)` or dark theme. The frame does not replace
caller-provided material tokens; it applies the explicit platform context and
reduced-motion policy while preserving the supplied visual theme.

Workload sections mirror each supplied resource record: one maximum-active-
background-jobs field, the server-provided upper bound, and Saved/Active values.
Do not derive extra capacity, reservation or waiting counts from a resource name.
The controller validates each resource independently and retains edits during
recovery; lowering a limit affects future admissions without interrupting active
jobs. The supplied resource list and provider identities remain domain-owned.
