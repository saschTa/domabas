# Authentication and namespace lifetime

The identity feature has immutable domain models and repository ports, generated
API data sources, repository adapters and separate presentation Cubits.
Public clients handle registration, login, restoration and explicit-token
revocation. `AppDependencies` creates a fresh
immutable-token dependency scope for each successful session, with identity and
document repositories owned by that scope.

Every user has a personal library. The library selector lists enabled namespace
memberships and displays role and ownership separately from system administration.
An invitation adds a membership without changing the current library. Managers
issue email-bound invitations, copy their one-time code and deliver it outside the
app; recipients paste the code while signed in. Invitation lists do not recover
secrets. Invitation copying uses an injected clipboard data source. HTTPS and
native clients use the platform clipboard; HTTP browsers use a temporary text
selection and copy command, restoring focus and removing the element afterward.
If the browser refuses clipboard access, the code remains selectable for manual
copying. Member forms use namespace roles and additional claims; owned memberships
are shown as immutable. System administrators have a separate user-management
screen for promotion and demotion, with no automatic access to foreign libraries.

`AccountWorkspace` owns navigation and feature Cubit lifetimes. The top bar
switches the active library and signs out. In Documents, the active library is
the page heading and the top bar offers Upload files and Create metadata under
their separate claims. A compact count and
refresh row starts the list; settings retain their own page headings.
User settings contains Libraries,
Members, Invitations and Password; Admin settings contains System users. These
destinations use the shared [presenter library](components.md), with a desktop
sidebar, tablet menus and mobile bottom navigation. Mobile Settings and Admin open
choosers for their permitted leaves and expose the current account identity.
Selection follows the current leaf; opening or cancelling a chooser preserves it.
Navigation does not animate between pages.

The app derives its allowed leaf IDs from the same groups supplied to the shell.
It rejects unknown, forbidden, initial-password and post-disposal callbacks before
loading any feature or changing selection. Namespace management supplies Members
and Invitations; only system management supplies Admin and System users. Neither
authority implies the other. Documents remains a limited-access landing page when
document-read permission is absent. Back dismisses an open chooser first; Back from
a settings page then returns to Documents.

The shell owns chooser and tablet popup routes on the session navigator. It checks
interaction identity and current group membership before accepting a result, and
removes only its exact route on resize or invalidation. Session replacement removes
all old routes and feature Cubits together. A stale menu callback cannot select a
page or dismiss a newer route.

Claim IDs are immutable string sets, not a closed transport enum. Named constants
drive current controls and scoped server catalog descriptors drive grant forms.
New registered backend claims can appear in identity responses without breaking
older clients. The backend checks the full role-plus-grants delegation ceiling;
visible controls are not an authorization boundary.

The server claim catalog supplies each claim's scope and included roles. Member
and invitation forms derive checked role permissions from that catalog, group them
by category and keep them locked while the role includes them. Direct grants remain
separate, including existing grants that overlap the selected role. Changing the
role therefore cannot silently discard an explicit grant.

System-user pages receive the installation-wide administrator count, including
users outside the current page. The Cubit disables demoting the last admin,
and disables role changes while the count is unknown. The backend remains the
authority for concurrent updates. A conflict refreshes the count and explains why
another administrator must be promoted first.

`DomabasApp` keys its whole MaterialApp/Navigator by the session. Switching obtains
a new bearer with the original expiry (including no expiry), then installs the entire returned
session and dependency scope. It removes old screens, dialogs, document Cubits
and member state together. Generation checks and exact-session callbacks prevent
a late switch/login, document response or 401 from installing old data or signing
out a newer session. Pending Cubits stop emitting after close.

A definite switch failure preserves the current library. If the server commits a
switch but its response is lost, the old bearer has been revoked; the next rejection
requires sign-in. The client does not pretend it can roll back that server state.
Other independently issued sessions keep their own namespaces. Browser tabs share
the persisted cookie; a new tab restores its current library. Switching rotates
that bearer, so an older tab with the old token must sign in again on rejection.

Sign-out clears protected UI and cancels document requests immediately. Its old
identity transport lives only until the
bounded server-revocation request finishes, then is disposed. Network failure still
removes local credentials and reports unconfirmed server revocation. Ordinary
replacement disposes the old scope immediately. Clients and Cubits are owned
instances; there is no service locator or mutable shared authorization header.

Startup restores credentials through `AuthRepository` and asks the server for a
fresh identity before showing protected content. An unavailable server preserves
credentials and presents retry or explicit local sign-out. Rejected credentials
are removed. Passwords and cached permissions are never persisted. Browser clients
send the explicit browser marker and credentials for the HttpOnly cookie flow;
native clients restore the bearer from the platform secure store. See
[platform storage](platforms.md) for the injected `SessionStore` boundary and host
requirements. Browser retention and clearing site data can remove the cookie.

New sessions have null expiry, so there is no routine expiry timer. Retained finite
sessions still expire while idle. The data source validates the raw required expiry
field before generated decoding: only explicit null means unlimited. A malformed
or missing value cannot silently become an unlimited session.

`SessionCubit` serializes server session operations and persistence writes.
It saves a returned token before installing the scope. Failed saves queue removal
and attempt revocation, and failed removal blocks further authentication until
retried. The browser stores only a nonsecret signed-out marker to prevent a failed
offline logout from restoring its uncleared cookie. Logout during a pending switch
revokes the replacement bearer if the server already issued it. New login remains
blocked until logout completes, so a late cookie clear cannot remove a newer login.

Initial-password sessions show only password change and sign-out. Successful
password change requires fresh login; wrong-current-password errors preserve the
session. Namespace role/grant/enabled updates and system-role updates revoke the
affected sessions. A successful self-update ends its current revoked scope.

Tests cover transport and extensible claim mapping, expiry/error handling, late
responses, logout lifetime, protected navigator replacement, role/claim forms,
invitation and administration flows, and browser workflows with personal and
shared libraries. See [backend identity](../backend/identity.md) for server policy,
capability delivery and migration details.

The document vocabulary repository belongs to the same authenticated library
scope as document reads. Composition injects it separately from the document
repository and cancels its requests on scope shutdown. Filter routes hold that
exact repository and Cubit owner; a replacement session or covered route cannot
apply a late selection. The vocabulary endpoint requires both document-read and
document-search authority, including its current database membership recheck.

General upload state is a separate session-owned Cubit. The app owns acquisition
leases so a cancelled scope cannot release a physically outstanding chooser,
portal lookup or read/transport early. Session busy immediately cancels that
scope's admission generation and queues; definite switch failure permits fresh
user selections without restarting cancelled work. A validated late acceptance
may update its surviving old-scope outcome and defer read invalidation until the
same scope is usable. A replacement scope receives neither outcome callbacks nor
old library refreshes. Upload-only scopes never perform document reads.
