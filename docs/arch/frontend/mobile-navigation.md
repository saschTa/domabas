# Mobile workspace navigation

Below 600 logical pixels, the workspace uses a floating bottom bar with Documents
fixed in the center. Its raised primary-action circle and curved surface remain the
normal layout when the permitted navigation has at most five groups.

The standard five entries are Invoices, Jobs, Documents, AI chat and Settings.
App composition supplies the primary order and filters destinations by claims;
the shared shell receives presentation values and never checks permissions itself.
Users without a primary claim see only their permitted destinations.

When a sixth group is present, such as Admin, keep Invoices, Jobs, Documents and
AI chat in the bar and replace secondary groups with one More button. Settings,
Admin and every future group outside the primary set belong in More. Adding
another secondary destination must never add a sixth bottom-bar button. With
five or fewer groups, retain the normal layout without introducing More.

Licenses is a leaf in User settings, available to every workspace role. It uses
the existing Settings chooser or More sidebar and adds no bottom-bar group.

More opens a rounded right sidebar. It shows each remaining group's heading and
its permitted leaf destinations directly, with a fixed Close control and a
scrollable list. Selecting a leaf closes the sidebar and highlights More in the
bar. Opening or dismissing the sidebar does not change the current destination.
Escape, system Back and the outside scrim dismiss it. Account utilities remain in
the header's separate More actions menu.

The sidebar shares the shell's exact-route ownership, stale callback protection,
permission-change invalidation and reduced-motion behavior. Crossing a responsive
breakpoint closes it without selecting a page. Focus returns only to a mounted
trigger. Tablet and desktop navigation continue to expose all permitted groups.

Retain at least 48-pixel targets, system safe insets and the user's text scale.
The five-button bar is 92 pixels high before outer spacing and safe insets. Only
use the accessible stacked fallback when measured labels do not fit, such as
narrow screens or enlarged text; cap its scrolling height at 40 percent of usable
height. Hide the bar while the software keyboard is open without replacing the
page or losing the chat draft. Content must be scrollable above the measured bar.

See [shared UI components](components.md#responsive-layout-and-navigation) for
shell layout, theme, interaction and content-inset rules.
