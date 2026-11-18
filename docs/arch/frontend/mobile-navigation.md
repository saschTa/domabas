# Mobile workspace navigation

The production workspace uses the Glacier mobile shell below 800 logical pixels.
Below 600px, a glass bottom bar contains permitted primary destinations; 600–799px
uses the 70px tablet rail. At enlarged text sizes the rail widens to 208px and
scrolls vertically, keeping the selected destination visible. Desktop begins at
800px and uses the collapsible sidebar. Layout follows available space while
scanner, sharing and keyboard interactions keep their platform-specific owners.

The standard primary entries are Invoices, Scanner, Documents, AI chat and More.
App composition filters these by current claims. Scanner requires upload permission
and Android or iOS scanner capability; it opens the existing scanner route without
changing the selected workspace. Closing it returns to that workspace. The shared
navigation receives display values and callbacks, never a permission repository.

Jobs, Settings, Administration and other secondary destinations live in More.
Its glass action-menu route also exposes current feature actions and account
utilities. Selecting a destination closes only that menu and invokes the current
callback; opening or dismissing it does not change the workspace. Escape, system
Back and the outside barrier dismiss it. Resize or owner changes invalidate stale
menu selections, and focus returns only to a surviving trigger on the current
route. User settings and Admin settings navigate to permission-filtered overview
pages. Desktop sidebar groups instead disclose their leaf links inline without
changing the current page. Overview cards open the same leaf routes; a parent
control returns to the overview while system Back retains the workspace's return
to Documents. The actual selected leaf continues to control refresh and feature
lifetime. Licenses remains available from settings for every workspace role.

The mobile header provides library selection and a named scoped Search action.
Documents and Invoices open their own draft-and-apply search dialogs; Cmd/Ctrl+K
uses the same current-route and capability guards. Menus and headers retain 48px
app targets, natural text scale and system safe insets. Large text uses bounded
scrolling instead of shrinking labels or covering the entire content viewport.

The navigation hides while a software keyboard is visible. Stable feature and
toolbar subtrees retain drafts and controllers through width and keyboard changes.
Collections scroll above measured navigation clearance. The compact Activity token
sits at the content's bottom right above navigation; trailing scroll extent lets
final actions remain reachable. Native document scanning and incoming-share
controllers retain their existing draft storage, permissions and upload lifetimes.

See [shared UI components](components.md#responsive-layout-and-navigation) and
[Glacier](glacier.md#responsive-behavior-and-checks) for current layout and material
contracts.
