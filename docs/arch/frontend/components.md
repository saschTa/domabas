# UI component library and responsive workspace

The [Glacier library](glacier.md) supplies the production frosted-glass components
and responsive screen compositions. `frontend/widgetbook/` hosts isolated
examples of the same presenters. Compatibility presenters remain available for
existing callers; their `glacier` option adopts the production material without
changing refresh, pagination or controller ownership.

Domabas builds its shared interface as a component library of **dumb presenters**
under `frontend/lib/ui/`. A presenter renders values and child widgets supplied by
its caller and forwards interaction through callbacks. It does not load data,
perform authorization, save settings or own an application session.

Feature screens compose these presenters and connect them to their Cubits.
The app composition root controls workspace navigation and the selected library.
The library provides a consistent visual language without becoming a second
application framework.

## Dependency boundary

```text
app composition → feature screens → shared UI presenters → Flutter Material
                        ↓
                 feature Cubits → domain repository ports
```

Shared UI code may import Flutter, `dart:ui` rendering primitives and other shared UI files. It must not import
feature domain models, Cubits, repositories, generated transport models,
clients, data adapters or `app/`. Pass strings, booleans, icons, immutable
presentation values, widgets and callbacks instead. Domain and data code must not
import the UI library. The frontend architecture test enforces these directions.

Presenters may hold local interaction state such as an open chooser or a collapsed
navigation group. Request state, selected library, permissions and feature-specific
selection stay in app composition or feature Cubits. Form controllers belong
to feature forms and must be disposed there. Theme constants are immutable values,
not global mutable dependencies.

## Components

Import `ui/domabas_ui.dart` from app or feature presentation code.

| Presenter | Responsibility |
| --- | --- |
| `GlacierTheme`, `GlacierTokens`, `AppElevation` and `AppLayout` | Production material roles, typography, shape, spacing and width thresholds; `AppTheme` remains a compatibility theme |
| `GlacierWorkloadFlow` | Selectable live pipeline-to-resource diagram. Connectors stack vertically on narrow screens and at large text sizes. |
| `AppWorkspaceShell` | Responsive navigation, persistent collection toolbar and account utilities |
| `GlacierToolbar` and feature-owned search dialogs | Quick filters, sort and collection actions; sidebar Search opens scoped draft criteria |
| `AppWorkspaceAction` and its button/menu presenters | Immutable action labels and current callbacks supplied by feature owners |
| `AppNavigationGroup` and `AppNavigationItem` | Immutable labels, icons, IDs and keys supplied by the caller |
| `AppPage` | Transparent full-height content pane, bounded action controls and independently scrolling content |
| `AppRefreshable` | Pull-to-refresh progress around a caller-owned vertical scroll view, with an awaited callback |
| `AppSurface` / `GlacierSurface` | Compatibility or edged glass material around caller-owned content |
| `AppSectionHeader` | Group title, short description and optional trailing control |
| `AppRecordRow` | List record with leading visual, text, metadata and responsive actions |
| `AppStatusBadge` | Labeled neutral, information, success, warning or danger state |
| `AppPipelineDiagram` and `AppPipelineStep` | Shared pipeline boxes, connectors, responsive layout and recorded step states |
| `AppEmptyState` and `AppNotice` | Empty content, information/status/error message, optional notice title and action |
| `AppPagedList` | Bounded visible pages, optional count footer, previous/next navigation and caller-owned continuation requests |
| `AppProgressSlot` | Permanent four-pixel space for foreground progress without moving or replacing adjacent content |
| `AppDialog` | Wide form frame with viewport-bounded scrolling and wrapping actions |
| `AppPaperCanvas` | Plain neutral root background without layout or input changes |
| `AppStripedProgressIndicator`, `AppStripedDivider` | Solid progress segment and fine section rule; existing presenter names preserve caller compatibility |
| `AppAppearanceMenu` | Theme choices, persistence feedback and retry with caller-owned state |

The [license reader](licenses.md) composes these same page, surface, record,
pagination and dialog presenters for searchable offline third-party notices.

Use Glacier buttons, named icon actions, rich choices and switches for ordinary
application controls. Keep existing Form-aware text fields, validators, autofill
and specialized viewer or native controls where their behavior is required. Add a new shared presenter when repeated product UI has an
established responsibility. Do not create generic abstractions for hypothetical
future screens or hide business logic in a component configuration object.

`AppPage` fills the remaining workspace with a transparent, clipped content pane.
Individual record and form cards sit directly on the root canvas. Do not wrap
collections or groups of cards in another surface; use spacing and section
headings to establish hierarchy. The selected
navigation item identifies the destination, so its title is a semantic label
instead of a repeated visible heading. Set `showHeading` for record details or
standalone setup that needs its own context. Actions remain in a fixed, bounded
control row and wrap at larger text sizes. The page itself has no scroll view.
`AppPage.child` receives bounded remaining height; collections use a lazy
`ListView` or `CustomScrollView` inside the pane. A primary controller supports
keyboard scrolling on every platform. Independent auxiliary scroll views set
`primary: false`. Forms inside `AppDialog` use the dialog's body scrolling.

Data screens supply `AppPage.onRefresh`; scrollable dialogs can supply
`AppDialog.onRefresh`. Independent panes use `AppRefreshable` directly. Ordinary
refresh buttons are replaced by a pull from the top of the vertical content.
The shared presenter keeps short and empty content draggable, waits for the
caller’s read to complete, and ignores nested scroll notifications. Its stable
scroll physics preserve scroll positions when refresh availability changes.
Empty states inside a list let the containing list own the gesture.
Keyboard users can use F5 or Ctrl/Cmd+R while focus is within the pane; assistive
technology receives a Refresh action. Explicit retry, conflict recovery and
installed-model discovery actions remain separate. Callers preserve drafts,
filters and the loaded pagination window when reloading data.

AppPage supplies a distinct PageStorage identity per title and body key. Inner
scroll offsets restore independently, so opening job details starts at the
outcome and returning preserves the position in older history. Chat messages
and the independent conversation history sit directly on the canvas. Pipeline
stages use the shared glass-edged diagram with recorded state colors.

For lists of separate cards, set `AppPage.insetBody` to false and apply
`AppLayout.cardListPadding(context)` to the list or scroll view. This keeps card
edges aligned within the content pane and preserves collection spacing.
The padding includes bottom navigation clearance. Keep viewport clipping enabled
so scrolled cards cannot paint over adjacent controls. Enclosed row lists keep the
default page insets. Dialogs own their padding inside the scrolling body.

## Unified pipelines and jobs

All pipeline types must use the same visual language in both their overview and
job detail view. Use `AppPipelineDiagram` with the same boxes, connectors, spacing,
typography and responsive vertical layout. Feature presenters supply step labels
and recorded states; they must not create a separate diagram style.

Jobs belong in one chronological list with an All pipelines option and filters
for each pipeline. Use the same record rows, status badges and Details action for
Paperless imports, email retrieval, document ingestion, AI processing and thumbnail generation. New pipeline types
must join this list instead of adding a separate list to the page. Permissions
still determine which jobs the user can see; mailbox and Paperless jobs remain
private to their owner.
The shared top bar exposes Pipeline and Status directly, with All filters opening
the full chooser. Both retain full server totals, stale/unknown count labels and
the existing immediate filtering behavior. An
app-owned filter Cubit shares selection between the toolbar and paginated history.
Pipeline setup follows the history in a collapsed section; opening it exposes
resource rules and all permitted source and document pipeline configuration.
Paperless history uses owner-scoped cursor pages and requires all of
the import, document-read and upload claims. Its Jobs Cubit refreshes on private
Paperless notifications while visible and foregrounded. Selected imports refresh
independently of the history window; item notifications refresh outcome pages. Fatal terminal records that did not retain
their earlier stage display Not recorded; per-file failures remain visible.

The Details action opens a feature-owned glass dialog while retaining the history
window underneath. It closes before a document, source account or import handoff,
and its exact route is removed when its owner is disposed. The content shows outcome and timing
first, then Pipeline for this attempt. Show completed, active, waiting and failed
steps from persisted evidence. Highlight the last recorded step when a run stops,
and expose per-item failures separately. Never infer completed work from a later
step when retries or partial results make that uncertain. Older records without
stage evidence say Not recorded. Acceptance into another pipeline means queued
downstream work, not that its processing has completed.

App composition combines feature-owned Cubits and presenters. The shared diagram
only receives presentation values. Paginated sources share a chronological
boundary, so older loaded records cannot appear ahead of newer unloaded jobs.

Jobs and pipeline administration show the same compact shared-resource summary.
Background jobs wait for worker and provider capacity before starting. Running
jobs continue when imports arrive. Job rows and details show recorded execution
status without the former High priority and Background policy badges. History
remains chronological. The interface never infers a specific job's blocked
resource or a global pause from the current user's visible jobs.

The expandable explanation distinguishes worker-only email/Paperless retrievals
from document ingestion and full reindexing, which also require Ollama, and AI
pipelines, which share their configured provider. Administrators edit capacity in
[Workload limits](workload-settings.md), where the server supplies shared limits,
active reservations and current pipeline requirements. Deprecated independent
ingestion/document AI concurrency values are no longer displayed as effective
capacity. Optional legacy scheduling data supplies only its provider retry count;
retries within a workflow remain distinct from a persisted document job attempt.

## Responsive layout and navigation

The shell's Activity dock overlays the bottom right of the full-height workspace.
Measured trailing scroll extent lets final records and actions reach above its
visible panel without shrinking the document viewport. Constrained layouts use
a compact token and an explicit Activity dialog. On phones the token clears
the navigation and keyboard. Upload receipts remain available from View uploads
after transient completion feedback disappears.

`AppJobSpinner`, `AppJobProgress` and `AppJobActivityCard` receive only display
values. Running badges and active pipeline steps share the spinner. Reduced
motion replaces indeterminate animation with a static icon or track. Reindex
progress has no percentage until enumeration completes; finished outcomes include
successes, failures, skipped and superseded entries. Scope labels distinguish
Current library from All libraries. A full bar never implies complete success.

The app-owned `JobActivityCubit` uses injected repositories and existing claims.
Each document, namespace/system reindex, email and Paperless source has its own
push-triggered refresh scheduler. Server aggregates supply totals independently
of the loaded rows. Active-only requests load a bounded page; Load more active
jobs extends it. Each notification replaces the loaded active window from fresh
pages, so terminal work disappears without individual record rotation. Slow or
failed sources do not block fresh results from other sources. Errors retain
previous evidence and expose Retry; disconnected progress is marked paused.

The monitor is independent of history filters, remains active across workspace
navigation, pauses with the application and dies with the authenticated scope.
It has no polling timer. Job and reindex counts stay separate because batches
contain document attempts and system batches span multiple libraries.

Breakpoints use available logical window width, never platform name or orientation.
Production uses the mobile shell below 800px and the desktop shell from 800px.
Below 600px, permitted primary destinations appear in the bottom bar; 600–799px
uses the tablet rail. Enlarged text widens the rail and allows bounded navigation
scrolling. Desktop uses a 224px sidebar or 76px collapsed rail. User settings and
Admin settings expand their permission-filtered leaf links inline in the sidebar.
Parent controls toggle disclosure without navigation or settings loads; selecting
a leaf keeps its group expanded. Rail activation expands the sidebar and reveals
the group. `AppNavigationGroup.items` retains the permitted leaf routes, and the
actual selected leaf ID remains owned by the workspace and its feature lifecycle.
`overview` supplies the optional parent landing page used by mobile More and leaf
back controls. Desktop overview cards have distinct keys from inline links.
Leaf pages retain a compact parent/back control in their floating glass toolbar.
Collapsing folds the utility row without moving icon anchors; reduced motion
removes transitions.

The phone primary destinations are Invoices, Scanner, Documents, AI chat and More,
filtered by real claims and available scanner support. Scanner opens its existing
route without changing the selected workspace. More exposes secondary destinations,
current feature actions, account context and utilities through the existing
owned action-menu route. Settings entries open their overview pages;
their leaf routes are not duplicated in More. The mobile header owns library
selection and Search.
Navigation hides while the keyboard is open, retaining feature State and drafts.
Use 48px app touch targets; real native window caption controls keep their separate
platform 44px contract.

Desktop Search sits below Domabas. Cmd/Ctrl+K opens search for the active Documents
or Invoices collection. Other destinations prefer authorized document search;
invoice-only users retain invoice search. The app checks the current owner route,
selected scope and capability before opening and again after any navigation.
A covered dialog or dirty reader cannot trigger navigation behind itself.
Feature toolbar States own query drafts and exact modal routes. Enter commits query
and filters atomically; quick filters remain immediate. Resize retains the field's
focus, controller and active IME composition. No global toolbar service or fixture
vocabulary is involved.

Quick filters, sorting and view actions occupy the floating collection toolbar.
Library, Activity and Appearance occupy the sidebar utility row, with additional
account and connection actions in the account menu. Library selection and library
management are separate operations. The selected sidebar destination supplies the
page context; repeated collection headlines are omitted.

Pages fill a bounded, clipped viewport. Collections and forms own their scrolling;
measured trailing activity clearance is appended inside that scroll flow. Settings
Save, pagination and Chat Send/Stop remain reachable above the bottom-right overlay.
Small headers and toolbars scroll within bounded space rather than consuming the
whole page. Dialog bodies and actions also remain reachable at narrow sizes and
large text. The shared dialog backdrop clears safe areas and the actual native
bar when present; exact feature-owned routes retain disposal and dirty guards.

Feature action menus keep current callbacks and state, dismiss only their own
route before invoking an action, and preserve browser upload gestures. Scope,
permission or owner changes invalidate stale selections. Focus returns only to a
surviving trigger on the current route. Refresh, selection and pagination continue
to belong to the existing feature Cubits.

## Visual and interaction rules

Glacier uses teal-tinted light and dark canvases, translucent glass navigation and
controls, explicit surface edges and DM Sans typography. Material roles and exact
tokens are documented in [Glacier](glacier.md). Source documents remain opaque and
retain their original colors. Backdrop filters are clipped to bounded surfaces;
avoid repeating blur on every collection item. Appearance persists the existing
light/dark/system mode; catalog-only background preferences are not exposed as
unbacked production settings.

Document hover draws a 1px accent edge. Rich choices use a softer selected edge,
strengthened on hover; disabled controls do not acquire hover feedback. Keyboard
focus uses its own 2px outline, while pointer selection does not retain that ring.
A nested Retry button owns its focus without also outlining the document opener.
These states must preserve layout, semantics and touch behavior. Ordinary sidebar
and button hover remains a fill change. Thin list separators, scanner guides and
semantic status labels remain meaningful. Keep danger, mixed, unknown, stale and
recorded-success states distinct.

Refresh feedback keeps its layout space. `AppProgressSlot` removes the inactive
indicator while retaining its bounds, and respects reduced-motion preferences.
Do not conditionally insert progress children ahead of lists, forms or viewers:
that moves content and can replace stateful children in lazy lists. Background
reads retain the last successful snapshot, including empty results. Their private
request flags do not disable visible actions; feature Cubits coordinate any action
that arrives during a read. Explicit refresh and initial loading remain visible.

Preserve Material keyboard focus, tooltips, popup dismissal and button semantics.
Keep interactive targets at least 48 pixels. Headings expose heading semantics;
selected navigation exposes selected semantics; notices use live regions. Use short transitions for meaningful state changes and hover/focus feedback.
Navigation hover/focus uses 140-millisecond tint and chevron transitions;
selection uses 180 milliseconds. Hit targets never move. Disable these transitions
and chooser animations when either MediaQuery's disable-animations preference or
the platform's reduce-motion preference is set, including runtime changes. Long identifiers must wrap or have accessible full labels,
and controls cannot depend on hover alone.

The feature, not the component library, combines role bundles and explicit grants.
Role-included claims appear checked and identified as included; additional grants
remain distinct. Backend policy remains authoritative even when the UI disables an
action such as demoting the last system administrator.

## Validation

Focused presenter tests cover desktop navigation, tablet nested menus, mobile
bottom navigation at 320 and 390 pixels, enlarged text, short windows, dialog scrolling and
independent row actions. Feature tests cover actual repository/Cubit behavior.
Inspect the running UI alongside automated checks. See the
[testing guide](../../development/testing.md) for commands and prerequisites.

## Growing collections

Every growing server collection must expose bounded pages with an accessible
continuation. Never substitute a larger hard limit for pagination. Jobs, email
syncs, reindex requests, Paperless imports and document outcomes render at most
20 rows through AppPagedList, with Previous and Next or Load more controls.
Identity and document collections retain their existing paginated lazy lists.
The library picker uses bounded visible pages; the fixed 40-entry local upload
cache shows ten outcomes per page. Configuration catalogs remain fixed lists.

Status filters query the server before pagination across document, email and
Paperless jobs. Changing status cancels pending reads and restarts each source at
its first matching page; late responses cannot restore the previous filter.
Paperless success excludes runs with failed files, which match Partially completed.
The combined jobs list uses every unfinished matching source's chronological boundary,
including Paperless. Loading an older page
retains existing records and cursors on failure. Automatic refresh keeps older
job and email-account pages in place, updates active records with bounded reads,
and leaves explicit refresh to return to the newest history.
