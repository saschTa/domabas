# Appearance and client preferences

Domabas offers System, Light and Dark appearance choices before and after sign-in.
The appearance action is available during session restoration, on authentication
and initial-password screens, in the workspace header and in document viewers and
inspectors. System follows runtime device brightness. Explicit choices remain
fixed until changed. The setting belongs to the app installation or browser origin,
independent of users, API endpoints and libraries.

## Ownership and storage

The `appearance` domain defines an immutable preference and a small repository
interface. Its data source owns a lazily constructed `SharedPreferencesAsync`
client from pinned `shared_preferences` 2.5.5. The repository translates strings
and storage failures. `AppDependencies` constructs the production repository;
`DomabasApp` owns one `AppearanceCubit` above the session-keyed MaterialApp.
Changing appearance does not recreate authenticated dependencies, the navigator,
feature Cubits, realtime connections or unsaved document drafts.

The single logical key is `domabas.appearance.v1`, containing `system`, `light` or
`dark`. Android uses DataStore Preferences, iOS uses NSUserDefaults, Linux and
Windows use the plugin's application data files, and web uses localStorage.
There is no credential, permission or document content in this setting. Sign-out
does not remove it and no bulk storage clear is used. Same-origin browser tabs
share the saved value but do not synchronize live; a newly opened app reads the
latest stored choice. Acknowledged platform writes are suitable for preferences
and do not promise survival of an immediate crash.

Missing, unknown and wrongly typed values fall back to System. Restoration runs
without blocking authentication or the first frame. After two seconds the UI
explains a pending read and stays usable. A late read cannot replace a subsequent
explicit choice. If it times out, its eventual value is discarded; retry becomes
available when the actual read settles. A failed plugin construction is retriable.

Selection applies immediately. The Cubit permits one real write in flight and
one coalesced latest pending choice. A two-second feedback deadline does not
release that ordering lock or cancel the platform call. When an old operation
settles, only the latest pending choice is written; obsolete success and failure
cannot acknowledge or revert the current choice. A settled failure offers retry
of the current choice. Storage failure never blocks app use. Disposal cancels UI
timers and fences callbacks, without waiting indefinitely for platform storage.

## Rendering and controls

`AppTheme` supplies paired semantic light and dark Material schemes. Shared
surfaces, navigation, input boundaries, statuses, processing cards and document
chrome resolve colors from the current theme. A five-color `AppSemanticColors`
extension supplies success and warning foreground/background pairs and the viewer
canvas. Studio uses achromatic white and charcoal surfaces, restrained orange
actions and borderless cards without shadows. Record and form cards sit directly
on the canvas; dialogs use spacing and headings for internal sections. Fields and secondary buttons
have filled resting states. Primary focus and error outlines retain two-pixel
borders; labels accompany state colors. `AppPaperCanvas` paints a plain neutral
background. The existing progress and divider presenters paint a solid rounded
progress segment and a fine section rule, with no dot or stripe decoration.
Document pixels retain their own opaque viewer canvas. Bundled Barlow Condensed
provides strong page headings; DM Sans supplies body text, navigation, controls
and form titles. The font files and their original OFL notices are included
locally, with no runtime font download. The light-mode primary role uses the
deeper Studio orange to keep small white action labels readable.
See [shared UI components](components.md) for surfaces and typography.

Appearance is passed to feature screens as an action widget. Foreign presentation
domains do not import its Cubit or storage implementation. The action opens a
retained dialog with its own Cubit subscription: selection, pending status and
retry update while it is open. It supports keyboard dismissal and focus return.
Narrow headers put library selection and wrapped utility actions on separate rows.

Theme changes preserve open routes. Mobile navigation and inspector sheets use
transparent route shells with semantic Material surfaces inside their live route
builders. Restoration and overlay helpers read their own themed contexts.
Theme transitions take 200 milliseconds and are disabled for runtime animation
and reduced-motion accessibility preferences. System brightness changes do not
write a new preference.

Only document chrome changes. PDF pages and image/thumbnail pixels are neither
inverted nor recolored. Transparent original pixels reveal the surrounding canvas.
Native launch screens and static web metadata precede Flutter preference loading;
the setting does not claim to control those earlier surfaces.

See [platform behavior](platforms.md) and the
[testing guide](../../development/testing.md) for platform prerequisites and checks.
