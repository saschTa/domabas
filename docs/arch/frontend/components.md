# UI component library and responsive workspace

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

Shared UI code may import Flutter and other shared UI files. It must not import
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
| `AppTheme`, `AppElevation` and `AppLayout` | Material colors, typography, flat surface styling, shape, spacing and width thresholds |
| `AppWorkspaceShell` | Responsive navigation, persistent collection toolbar and account utilities |
| `AppCollectionToolbar` and `AppSearchField` | Consistent caller-owned search, filter controls and active summaries, with the library picker on the right |
| `AppWorkspaceAction` and its button/menu presenters | Immutable action labels and current callbacks supplied by feature owners |
| `AppNavigationGroup` and `AppNavigationItem` | Immutable labels, icons, IDs and keys supplied by the caller |
| `AppPage` | Fixed full-height content pane, bounded action controls and independently scrolling content |
| `AppRefreshable` | Pull-to-refresh progress around a caller-owned vertical scroll view, with an awaited callback |
| `AppSurface` | Flat themed panel with rounded corners and a fine neutral outline |
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

Use Flutter's existing buttons, text fields, menus and selection controls inside
these components. Add a new shared presenter when repeated product UI has an
established responsibility. Do not create generic abstractions for hypothetical
future screens or hide business logic in a component configuration object.

`AppPage` fills the remaining workspace with a fixed surface. The selected
navigation item identifies the destination, so its title is a semantic label
instead of a repeated visible heading. Set `showHeading` for record details or
standalone setup that needs its own context. Actions remain in a fixed, bounded
control row and wrap at larger text sizes. The page itself has no scroll view.
`AppPage.child` receives bounded remaining height; collections use a lazy
`ListView` or `CustomScrollView` inside the surface. A primary controller supports
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
outcome and returning preserves the position in older history. Chat sets
`surface: false` because its transcript and history already supply separate
full-height surfaces.

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
The shared top bar opens the Jobs filter dialog. Its pipeline and status choices
retain full server totals and the existing immediate filtering behavior. An
app-owned filter Cubit shares selection between the toolbar and paginated history.
Pipeline setup follows the history in a collapsed section; opening it exposes
resource rules and all permitted source and document pipeline configuration.
Paperless history uses owner-scoped cursor pages and requires all of
the import, document-read and upload claims. Its Jobs Cubit refreshes on private
Paperless notifications while visible and foregrounded. Selected imports refresh
independently of the history window; item notifications refresh outcome pages. Fatal terminal records that did not retain
their earlier stage display Not recorded; per-file failures remain visible.

The Details action opens the same Job details page structure: outcome and timing
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

The shell's Activity card uses the Scaffold floating action slot, so it clears
the measured phone navigation and keyboard. It is at most 280 pixels wide and
opens one paginated, scrollable panel for uploads, jobs and reindex requests.
Short windows and enlarged text use a compact row. Upload receipts remain
available from View uploads after transient completion feedback disappears.

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

| Width | Navigation | Page inset |
| --- | --- | --- |
| Below 600 | Floating bar with up to five entries and centered Documents; additional secondary groups share More | 16 |
| 600–1099 | 80-pixel rail; settings open nested destination menus | 24 |
| At least 1100 | 224-pixel sidebar with expandable settings groups | 32 |

Workspace pages fill the available width with the responsive insets above.
Document grids add columns on wide screens; focused forms, search inputs and
dialogs retain their own readable width limits. Collection toolbars put search,
filters, sorting and view controls beside the right-aligned library picker on wide
screens. Compact layouts put search and the library picker on the first row and
controls on a second row. Secondary actions move into More as width shrinks.
The shell receives an explicit `toolbarBuilder`; feature toolbar widgets own their
controllers and dialog routes and read the same Cubit state as the collection.
Search and filter controls are not registered through a global toolbar service.
Rows move their actions below the text
when their available width is below 560 pixels or text is enlarged. Dialogs default
to 720 pixels and stay inside a narrow viewport. Shared dialogs own a safe-area
boundary so raw dialog routes also clear notches and system bars; Flutter's dialog
insets continue to handle the keyboard. Custom raw dialog frames must provide the
same safe-area boundary. Member and invitation forms use
860 pixels, with two permission columns when space and text size allow it.

The [mobile navigation rules](mobile-navigation.md) keep Invoices, Scanner,
Documents, AI chat and More in the phone bar when available. Scanner requires
upload permission and native scanner support; it opens the scanner without
changing the selected workspace. Jobs, Settings, Admin and future secondary
groups are available through More even when the bar has fewer than five entries.
Desktop and tablet navigation retain their existing destinations.

The workspace has Documents and nested User settings destinations for Libraries,
Members, Invitations and Password. Members and Invitations refer to the selected
library and require the corresponding management claim. Admin settings contains
System users and requires system authority. The top bar switches libraries; it
does not contain library-management actions. Appearance, live updates, Your jobs
and Sign out occupy four labeled-by-tooltip icons in the desktop sidebar footer.
The rail groups these utilities under Account; phones include them in the sidebar
opened by the bottom More button, alongside the current workspace's actions.

Documents fills a fixed pane with its internally scrolling collection; the library
picker stays on the right of the toolbar. Upload is the primary action, becoming an icon beside the
collection controls and a More entry when space is limited. Scan, New document
and Upload history remain available in More. The selector uses one visible line
with its complete library/account context in semantics. Settings use the same
fixed AppPage surface and retain meaningful section labels. Shared UI receives immutable action values, current callbacks
and widgets, never a document Cubit or permission object.

Feature action builders keep appearance, activity and connection state mounted
above the shell. Opening or closing More does not dispose those owners. The menu
updates its current rows for busy state, badges and connection changes. It owns
one exact route and generation, rejects covered or stale callbacks, and invalidates
on owner, action-set, viewport or text-scale changes. Activation removes only that
route and invokes the current callback synchronously, preserving browser upload
gestures. Focus returns after the feature action completes, only to a surviving
trigger on the current owner route. Menus have a fixed Close control and scrollable
natural-scale rows with targets of at least 48 pixels.

The shell receives allowed navigation entries and the selected ID. It neither
checks claims nor constructs feature screens. Navigating replaces the selected
body without swipe tabs or custom page transitions. Ordinary navigation keeps the
same authenticated dependency scope; sign-out, expiry and library switching still
replace the entire session-keyed MaterialApp/Navigator subtree.

Groups have stable IDs independent of their full and compact labels. The selected
primary group follows the selected leaf; opening or cancelling a chooser does not
select a page. On normal phone widths, Documents is a permanent raised accent
circle above a curved cutout in the rounded surface. Permitted destinations fill
the two sides; a separate marker identifies the selected group, including Documents.
Labels use the user's natural text scale. Their actual measured width and height
determine whether the cutout layout fits. Narrow or enlarged-text layouts use a
full-width Documents row above paired or full-width destinations. Scroll the bar when its
contents exceed 40 percent of usable height, with its margin and bottom safe inset
inside that budget. Focused buttons scroll into view. The body extends behind the
bar, so content remains visible through its notch and outer margins. The bar has
eight pixels of bottom spacing above the system safe inset. Page surfaces also
stop above the physical bottom safe inset so their corners stay visible on iPhone;
their inner scrolling content retains the remaining navigation clearance. Scaffold
supplies the bar's measured height as bottom MediaQuery padding. Settings lists
consume it automatically; the document footer and password form include it inside
their scrollable content. Final rows and actions can scroll above the bar without
reserving a solid footer strip. Keep the extended body enabled across keyboard
and width changes to preserve the child subtree. The bar hides while a software
keyboard is visible and returns with selection and drafts intact.

Navigation buttons own their hover, press and focus decoration without a second
Material overlay. Transparent decoration endpoints retain the visible endpoint's
color channels so intermediate frames do not darken during alpha interpolation.
The raised center uses an outline for interaction feedback, preserving the cutout.
Desktop sidebar and tablet rail items share the document cards' primary hover
outline without shadows or translation. Pointer exit removes
the outline, including after a click; the selected fill and keyboard feedback
remain. Navigation hit targets and positions remain fixed.

Collection toolbars scroll within a bounded height in short windows: at most
40 percent of the available height, capped at 256 pixels including padding.
The default header for pages without collection controls stays on one row.
`AppPage` bounds its fixed action controls to 40 percent of the height above
navigation, capped at 240 pixels. Oversized controls scroll within that row,
leaving the content pane available. The pane extends behind the mobile bar;
inner lists include bottom clearance so final rows remain reachable. The document
toolbar and pagination also keep their controls bounded. Text scaling remains
natural in short windows.

Mobile choosers have a fixed close control above a scrollable heading, account label
and permitted destinations. Tablet menus retain their anchored native popup. The
shell owns each exact route and an interaction generation, validates returned IDs
against current groups, and ignores stale callbacks. Resize, membership changes and
motion-preference changes invalidate and remove only that route. Focus returns to a
surviving group trigger after dismissal or resize; disposal restores nothing.

## Visual and interaction rules

Studio uses an achromatic `#F5F5F5` canvas, `#FFFFFF` surfaces and `#232323`
text. Dark mode uses `#181818`, `#222222` and `#F0F0F0` respectively. Orange
provides focus, selection and primary actions. The light primary role is
`#B83E23` so small white action labels retain contrast; dark mode uses `#FF8869`
with dark foreground text. Presenters resolve semantic roles at build time,
including matching status foreground/background pairs. Read
[appearance and client preferences](appearance.md) for lifetime and persistence.

Panels and dialogs use rounded corners and fine neutral outlines. Ordinary
buttons retain 12-pixel corners. AppElevation retains its existing API but returns
no shadows. Surfaces have no texture, blur or hover lift. Locally bundled Barlow
Condensed provides display and page headings; DM Sans supplies body text,
navigation, control labels and form titles. Destination headings are omitted;
record details and standalone setup can show a heading. Form sections use a fine
neutral rule. The root canvas is a plain fill.
Progress uses a solid rounded segment with transparent remaining space and
preserves determinate, RTL and reduced-motion behavior.

Filled inputs, secondary buttons and chips retain focus, selection and error
indicators. Focus and error outlines remain two pixels wide. Pipeline current
and failed stages also retain stronger semantic edges. Document and navigation
highlights retain primary rings for pointer and keyboard use. Thin list
separators, checkbox/radio geometry and scanner guides remain meaningful. Use
semantic state labels alongside color.

Refresh feedback keeps its layout space. `AppProgressSlot` removes the inactive
indicator while retaining its bounds, and respects reduced-motion preferences.
Do not conditionally insert progress children ahead of lists, forms or viewers:
that moves content and can replace stateful children in lazy lists. Background
reads retain the last successful snapshot, including empty results. Their private
request flags do not disable visible actions; feature Cubits coordinate any action
that arrives during a read. Explicit refresh and initial loading remain visible.

Preserve Material keyboard focus, tooltips, popup dismissal and button semantics.
Keep interactive targets at least 48 pixels. Headings expose heading semantics;
selected navigation exposes selected semantics; notices use live regions. Use short transitions for meaningful state changes and hover/focus outlines.
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
