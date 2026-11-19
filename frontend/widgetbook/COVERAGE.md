# Catalog coverage contract

This catalog covers the desktop, mobile and native-frame reusable widget families
and the current product's screen families. Its fixtures exercise the UI contract;
they do not reproduce backend authorization, persistence or background workers.
Production routes continue using their existing Cubits and adapters.

The `desktop-workspace` entry composes the same domain examples inside the
Glacier shell. Other entries isolate each component or important state. Use the
Widgetbook theme, viewport, text-scale and motion controls to compare them.

Visual acceptance requires matched light/dark screenshots of the approved design
and the composed Flutter screens, including open modals. Check surface opacity,
edge borders, backdrop visibility, control density, content geometry and routing.
Registration and overflow tests establish coverage and layout safety; they do not
establish visual fidelity. Isolated examples use the same ambient canvas so glass
can be assessed in context.

## Product screens and states

| Product family | Existing product source | Catalog examples and capabilities |
| --- | --- | --- |
| Workspace | `app/account_workspace.dart`, `ui/app_workspace_shell.dart` | Complete desktop composition; expanded/collapsed navigation, inline expandable settings/admin with active-child reveal, compact drawer, sidebar search and utilities |
| Documents | `presentation/document/views/documents_screen.dart` | Grid/list, type/tag/address filters, sorting, status/retry, empty/no-match/loading/stale/error/denied, continuation |
| Original reader | `presentation/document/widgets/document_detail_dialog.dart`, `document_canvas.dart` | Original/Text, PDF page/zoom/fit/find, real PDF engine integration, injected original/image/email/locked/missing/error states, direct properties/links/processing, top actions |
| Document editing | `document_properties_panel.dart`, `document_editor_dialog.dart`, `document_ocr_panel.dart` | Complete metadata fields, tags, extracted text, revision, error/conflict/uncertain/deleted recovery contracts |
| Uploads | `document_upload_host.dart` | Queue and per-file receipt: waiting, reading, uploading, accepted, rejected, duplicate, unknown outcome |
| Invoices | `presentation/invoice/views/invoices_screen.dart`, `widgets/invoice_details_dialog.dart` | Criteria/collection, exact amount+currency, parties, lines, tax, allowances, payment, notes, references, provenance, bounded groups |
| Jobs | `presentation/document/views/document_processing_screen.dart`, email/Paperless job presenters | Unified history, five pipeline families, recorded stages, per-item outcomes, known/unknown causes, retry/open callbacks, pagination |
| Activity/reindex | `presentation/identity/widgets/personal_activity_action.dart`, `ui/app_job_progress.dart` | Independent activity, stale/retry, upload versus processing, enumeration/unknown total, partial outcomes and scope |
| Conversations | `presentation/chat/views/chat_screen.dart` | Empty/current/disabled/uncertain chat, history, selectable messages, trusted sources, fixed composer, send/stop/check, earlier history/messages, keyboard/IME |
| Authentication/session | `presentation/identity/views/auth_screen.dart`, `app/domabas_app.dart` | Sign-in/register, invalid credentials, restore/expiry recovery, password change and validation |
| Server | `presentation/server/views/server_configuration_screen.dart` | Native setup/change, validation/reload/pending, hosted-browser restriction |
| Libraries/access | `presentation/identity/views/libraries_screen.dart`, `members_screen.dart` | Current/shared library, members, role-included versus explicit grants, invitations/code/expiry/revocation, scoped confirmations |
| System users | `presentation/identity/views/system_users_screen.dart` | Independent system authority, last-admin restriction and changed/unknown counts |
| Email | `presentation/email/views/email_providers_screen.dart`, `widgets/email_provider_editor.dart` | Accounts, IMAP fields, credential retention/replacement, import rules, consent renewal, source checks and uncertain outcomes |
| Paperless | `presentation/paperless/views/` | Source/token configuration, import outcomes, retrieval limits and save/reconciliation states |
| AI and processing settings | `presentation/chat/views/chat_settings_screen.dart`, `presentation/document/views/document_processing_settings_screen.dart` | Independent model/provider/context/credential settings, OCR/extraction switches, configuration conflict/unknown outcomes, scoped reindex |
| Workload | `presentation/workload/views/workload_settings_screen.dart` | Desktop and phone workload screens with selectable pipeline flow, shared resource occupancy, simulated ingestion load, bounded pipeline and resource limits, save/reset and recovery |
| Appearance/account/live updates | `presentation/appearance/`, `presentation/realtime/`, app account composition | System/light/dark, material/background preferences, persistence failure, account menu, connection context |
| Licenses | `presentation/licenses/views/licenses_screen.dart` | Search/continuation, selectable notices, empty/error, independent catalog dependency notices |

## Public presenter inventory

Every public widget under `frontend/lib/ui/glacier/` must have its own exact
`widgetType` registration. `test/coverage_test.dart` compares the source inventory
with registrations and rejects omissions; `test/catalog_test.dart` renders all
registered examples across the representative layout matrix. Presentation value
objects and theme extensions are exercised through their owning widgets. The
current inventory contains 140 public widgets: 71 desktop/shared, 61 mobile and eight
native presenters or inherited contexts.

| Source file | Reusable public widgets |
| --- | --- |
| `glacier_controls.dart` | GlacierButton, GlacierIconButton, GlacierChoice, GlacierSwitchRow, GlacierField, GlacierTag |
| `glacier_surfaces.dart` | GlacierSurface, GlacierSection, GlacierDialog, GlacierToolbar, GlacierEmpty, GlacierActivityBackdrop |
| `glacier_workspace.dart` | GlacierWorkspace |
| `glacier_workspace_geometry.dart` | GlacierWorkspaceGeometry |
| `glacier_documents.dart` | GlacierDocumentCard, GlacierDocumentRow, GlacierDocumentCollection, GlacierPropertyGrid, GlacierRelatedDocuments, GlacierUploadQueue, GlacierDocumentPropertiesForm |
| `glacier_reader.dart` | GlacierReader, GlacierPdfToolbar, GlacierFindBar, GlacierOriginalState, GlacierExtractedText |
| `glacier_search.dart` | GlacierSearchDialog, GlacierSearchFilterGroup, GlacierActiveFilters, GlacierVocabularyPicker |
| `glacier_invoices.dart` | GlacierInvoiceRow, GlacierInvoiceSection, GlacierInvoiceRecords, GlacierInvoiceDetails |
| `glacier_workload_flow.dart` | GlacierWorkloadFlow |
| `glacier_settings.dart` | GlacierSettingsPage, GlacierSettingsSection, GlacierSettingsOverview, GlacierSettingsHeader, GlacierFieldGrid, GlacierSettingsRecord, GlacierIdentityContext, GlacierPermissionGroup, GlacierMemberEditor, GlacierInvitationCode, GlacierCredentialField, GlacierAuthPanel, GlacierRecoveryPanel, GlacierPasswordFields, GlacierServerForm, GlacierAppearancePreferences, GlacierModelConnection, GlacierEmailAccountForm, GlacierWorkloadResource, GlacierCapacityMeter, GlacierLicenseReader, GlacierAccountMenu |
| `glacier_workflows.dart` | GlacierPipelineTimeline, GlacierJobRow, GlacierJobsScreen, GlacierJobDetails, GlacierJobOutcome, GlacierReindexProgress, GlacierActivityPanel |
| `glacier_chat.dart` | GlacierConversationHistory, GlacierChatMessage, GlacierChatComposer, GlacierChatScreen |
| `glacier_activity_dock.dart` | GlacierActivityDock |
| `glacier_preview_placeholder.dart` | GlacierPreviewPlaceholder, GlacierPreviewRetry |
| `glacier_native_frame.dart` | GlacierNativeFrame, GlacierNativeTitleBar, GlacierNativeCaptionControls, GlacierNativeDragRegion, GlacierNativeCompactNavigation, GlacierNativeCommandFeedback |
| `glacier_native_values.dart` | GlacierNativePresentationScope, GlacierNativeContentInsets |
| `glacier_mobile_workflows.dart` | GlacierMobileInvoiceRow, GlacierMobileInvoiceFilters, GlacierMobileInvoicesScreen, GlacierMobileInvoiceSection, GlacierMobileInvoiceDetails, GlacierMobileActivitySummary, GlacierMobileJobRow, GlacierMobilePipelineEvidence, GlacierMobileJobDetails, GlacierMobileJobsScreen, GlacierMobileReindexScreen |
| `glacier_mobile_capture.dart` | GlacierMobileScanHandoff, GlacierMobileScanPage, GlacierMobileScanReview, GlacierMobileUploadForm, GlacierMobileUploadOutcome, GlacierMobileUploadReceipts, GlacierMobileIncomingShare, GlacierMobileShareExtension |
| `glacier_mobile_settings.dart` | GlacierMobileSettingsSection, GlacierMobileSettingsForm, GlacierMobileSelectField, GlacierMobilePermissionChoice, GlacierMobileDisclosure, GlacierMobileAppearance, GlacierMobileProviderFields, GlacierMobileImportOutcome |
| `glacier_mobile_reader.dart` | GlacierMobileReaderToolbar, GlacierMobileOriginalCanvas, GlacierMobileReaderFindBar, GlacierMobileReader, GlacierMobileDocumentProperties |
| `glacier_mobile_foundations.dart` | GlacierMobileSurface, GlacierMobileHeader, GlacierMobileNavigation, GlacierMobileShell, GlacierMobileActionBar, GlacierMobileSheet, GlacierMobileSearchEntry, GlacierMobileRecordRow, GlacierMobileField, GlacierMobileFieldGroup, GlacierMobileNotice, GlacierMobileContinuation, GlacierMobileConfirmation |
| `glacier_mobile_identity.dart` | GlacierMobileLibraryRow, GlacierMobileMemberRow, GlacierMobileAuthForm, GlacierMobileServerEditor, GlacierMobileAccessEditor, GlacierMobileInvitation |
| `glacier_mobile_chat.dart` | GlacierMobileChatMessage, GlacierMobileChatComposer, GlacierMobileChatHistoryRow, GlacierMobileChatHistory, GlacierMobileChatScreen |
| `glacier_mobile_documents.dart` | GlacierMobileDocumentFilters, GlacierMobileDocumentCard, GlacierMobileDocumentSelectionBar, GlacierMobileDocumentCollection, GlacierMobileSearchFilters |

Existing AppNotice, AppStatusBadge, AppPagedList, AppProgressSlot, AppRefreshable,
AppJobSpinner/AppJobProgress and AppModelContextField remain shared rather than
being copied into new equivalents. They appear in foundation/domain examples.

## Mobile reference coverage

Mobile cases use `mobile-<screen>-<state>` identities. The frozen reference
inventory in `test/fixtures/glacier_mobile_reference.json` records 42 screen
families, 176 named states and 45 reusable component contexts. Each named state
has a dedicated case; standalone component cases carry `referenceComponent`
metadata. `test/mobile_coverage_test.dart` checks exact state and context coverage
alongside the public presenter inventory test.

The Mobile host addon selects iOS or Android, safe-area simulation and keyboard
simulation independently of viewport width. Direct previews accept `platform=ios`
or `platform=android`, `safe=true|false`, `keyboard=true|false`, `textScale=2`,
`appearance=light|dark`, `motion=reduced` and `opaque=true`. A direct `case` query
removes catalog chrome. Safe fixtures use 44/34 logical pixels for iOS and 24/24
for Android; keyboard fixtures reserve 280 pixels. These are explicit browser
simulations, not evidence of native keyboard, Back, scanning or sharing behavior.

`test/mobile_host_test.dart` exercises every named state in both platform contexts,
including narrow enlarged text and tablet layouts. Identity/settings behavior
tests cover retained recovery drafts, inherited permissions, registration drafts
and license filtering; the document and workflow domains own their interaction
tests. Visual acceptance still requires matched reference captures and a
component-by-component review.

## Native desktop frame coverage

The native reference inventory in `test/fixtures/glacier_native_reference.json`
contains 72 exact frame cases, six presenter contracts and three interaction
contexts. Each `native-<platform>-<state>` case supplies its platform, theme,
window mode and text scale; set the browser viewport to the inventory dimensions.
The examples reuse the desktop domain presenters and their catalog callbacks.

| Public widget | Named catalog example |
| --- | --- |
| GlacierNativeFrame | `native-component-window-frame` |
| GlacierNativeTitleBar | `native-context-titlebar` |
| GlacierWorkspaceGeometry | `native-context-workspace-geometry` |
| GlacierNativeCaptionControls | `native-component-caption-controls` |
| GlacierNativeDragRegion | `native-component-drag-layout` |
| GlacierNativeCompactNavigation | `native-component-compact-navigation` |
| GlacierNativeCommandFeedback | `native-component-window-command-state` |
| GlacierNativePresentationScope | `native-context-presentation-scope` |
| GlacierNativeContentInsets | `native-context-content-insets` |

The native and shared geometry inherited contexts are public widgets with composed
examples. They belong to the existing frame and layout contracts. The sixth
reference contract, preview controls, is catalog-only. The public inventory
test includes inherited widgets as well as stateful and stateless presenters.
Native commands are simulated callbacks; host decorations, system menus,
dragging, resize edges and operating-system focus require platform verification.

## Scope boundaries

- Public widgets render supplied values and callbacks. Controls whose outcomes
  require a real repository demonstrate callback/confirmation/recovery contracts
  with fictional state. They do not claim a persisted operation succeeded.
- The real PDF-engine example complements deterministic source artwork used for
  layout review. Production adapters retain PDF selection, binary transport,
  original loading and search result ownership.
- Desktop coverage includes narrow fallback and enlarged text. Camera scanning,
  OS sharing, secure storage, native server transport and host-specific gestures
  continue in the existing six-platform client and need native verification.
- Ambient activity consumes supplied values; a production aggregate API is not
  introduced by this library. No invented activity is inserted into production.
- State examples and automated layout checks do not constitute screen-reader,
  browser-wide, native-platform or production end-to-end certification.
