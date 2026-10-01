import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/identity/datasources/identity_clipboard_data_source.dart';
import '../domain/document/models/document_capabilities.dart';
import '../presentation/chat/cubits/chat_cubit.dart';
import '../presentation/chat/cubits/chat_settings_cubit.dart';
import '../presentation/chat/views/chat_screen.dart';
import '../presentation/chat/views/chat_settings_screen.dart';
import '../domain/email/models/email.dart';
import '../domain/paperless/models/paperless.dart';
import '../domain/realtime/models/realtime.dart';
import '../presentation/invoice/cubits/invoices_cubit.dart';
import '../presentation/invoice/views/invoices_screen.dart';
import '../presentation/licenses/cubits/licenses_cubit.dart';
import '../presentation/licenses/views/licenses_screen.dart';
import '../presentation/realtime/cubits/realtime_cubit.dart';
import '../presentation/realtime/widgets/realtime_status_action.dart';
import '../presentation/identity/cubits/current_identity_cubit.dart';
import '../presentation/document/views/documents_screen.dart';
import '../presentation/document/cubits/documents_cubit.dart';
import '../presentation/document/cubits/document_processing_cubit.dart';
import '../presentation/document/cubits/document_processing_settings_cubit.dart';
import '../presentation/document/views/document_processing_screen.dart';
import '../presentation/document/views/document_processing_settings_screen.dart';
import '../presentation/document/widgets/document_detail_dialog.dart';
import '../domain/identity/models/identity.dart';
import '../presentation/identity/cubits/account_cubit.dart';
import '../presentation/identity/views/libraries_screen.dart';
import '../presentation/identity/cubits/libraries_cubit.dart';
import '../presentation/identity/widgets/library_switcher.dart';
import '../presentation/identity/views/members_screen.dart';
import '../presentation/identity/widgets/password_form.dart';
import '../presentation/identity/views/system_users_screen.dart';
import '../presentation/identity/cubits/system_users_cubit.dart';
import '../ui/domabas_ui.dart';
import '../domain/identity/models/personal_activity.dart';
import '../presentation/email/cubits/email_providers_cubit.dart';
import '../presentation/email/cubits/email_jobs_cubit.dart';
import '../presentation/email/widgets/email_jobs.dart';
import 'processing_jobs_list.dart';
import '../presentation/email/widgets/email_pipeline.dart';
import '../presentation/email/views/email_providers_screen.dart';
import '../presentation/paperless/views/paperless_import_screen.dart';
import '../presentation/paperless/cubits/paperless_jobs_cubit.dart';
import '../presentation/paperless/cubits/paperless_settings_cubit.dart';
import '../presentation/paperless/views/paperless_settings_screen.dart';
import '../presentation/workload/cubits/workload_settings_cubit.dart';
import '../presentation/workload/views/workload_settings_screen.dart';
import '../presentation/paperless/widgets/paperless_jobs.dart';
import '../presentation/paperless/widgets/paperless_pipeline.dart';
import '../presentation/identity/cubits/personal_activity_cubit.dart';
import '../presentation/identity/widgets/personal_activity_action.dart';
import '../presentation/scanner/cubits/scanner_cubit.dart';
import '../presentation/scanner/views/scanner_screen.dart';
import 'app_dependencies.dart';
import 'scanner_scope.dart';
import 'workspace_cubit.dart';
import '../presentation/document/cubits/document_uploads_cubit.dart';
import 'job_activity_cubit.dart';
import 'job_activity_indicator.dart';

final class AccountWorkspace extends StatefulWidget {
  const AccountWorkspace({
    super.key,
    required this.session,
    required this.dependencies,
    required this.onLogout,
    required this.onSessionEnded,
    required this.onSwitch,
    this.appearanceAction,
    this.appearanceWorkspaceAction,
    this.serverAction,
    this.serverSettings,
    this.onUpload,
  });
  final AuthSession session;
  final AuthenticatedDependencies dependencies;
  final VoidCallback onLogout;
  final void Function(String) onSessionEnded;
  final Future<String?> Function(String) onSwitch;
  final Widget? appearanceAction;
  final AppWorkspaceAction? appearanceWorkspaceAction;
  final Widget? serverAction;
  final Widget? serverSettings;
  final VoidCallback? onUpload;

  @override
  State<AccountWorkspace> createState() => _AccountWorkspaceState();
}

final class _AccountWorkspaceState extends State<AccountWorkspace>
    with WidgetsBindingObserver {
  late final CurrentIdentityCubit _identity;
  final _invitationClipboard = IdentityClipboardDataSource();
  late final ChatCubit _chat;
  late final ChatSettingsCubit _chatSettings;
  late final RealtimeCubit _realtime;
  late final StreamSubscription<RealtimeState> _realtimeSubscription;
  late final StreamSubscription<Identity> _identitySubscription;
  Timer? _fallback;
  late final DocumentsCubit _documents;
  late final InvoicesCubit _invoices;
  late final LicensesCubit _licenses;
  late final AccountCubit _account;
  late final LibrariesCubit _libraries;
  late final SystemUsersCubit _systemUsers;
  late final DocumentProcessingCubit _processing;
  late final EmailProvidersCubit _email;
  late final EmailJobsCubit _emailJobs;
  late final PaperlessJobsCubit _paperlessJobs;
  late final PaperlessSettingsCubit _paperlessSettings;
  late final WorkloadSettingsCubit _workloadSettings;
  late final PersonalActivityCubit _activity;
  late final DocumentProcessingSettingsCubit _processingSettings;
  late final JobActivityCubit _jobActivity;
  int _activityView = 0;
  bool _activityBatches = false;
  bool _foreground = true;
  bool _documentRoute = false;
  bool _scannerRoute = false;
  ScannerScope? _scannerScope;
  ScannerCubit? _scannerCubit;
  bool get _coveredRoute => _documentRoute || _scannerRoute;
  final WorkspaceCubit _navigation = WorkspaceCubit();
  String get _destination => _navigation.state;

  @override
  void initState() {
    super.initState();
    final identity = widget.session.identity;
    WidgetsBinding.instance.addObserver(this);
    _licenses = LicensesCubit(widget.dependencies.licenses);
    _chat = ChatCubit(
      widget.dependencies.chat,
      allowed: identity.allows(IdentityPermission.useChat),
    );
    _chatSettings = ChatSettingsCubit(
      widget.dependencies.chat,
      allowed: identity.allows(IdentityPermission.manageChat),
    );
    _invoices = InvoicesCubit(
      widget.dependencies.invoices,
      allowed: identity.allows(IdentityPermission.readInvoices),
    );
    _paperlessJobs = PaperlessJobsCubit(
      widget.dependencies.paperless,
      allowed:
          identity.allows(IdentityPermission.importPaperless) &&
          identity.allows(IdentityPermission.readDocuments) &&
          identity.allows(IdentityPermission.uploadDocuments),
    );
    _paperlessSettings = PaperlessSettingsCubit(
      widget.dependencies.paperlessSettings,
      allowed: identity.allows(IdentityPermission.managePaperless),
    );
    _workloadSettings = WorkloadSettingsCubit(
      widget.dependencies.workloadSettings,
      allowed: identity.allows(IdentityPermission.manageWorkloads),
    );
    _emailJobs = EmailJobsCubit(
      widget.dependencies.email,
      allowed: identity.allows(IdentityPermission.manageEmail),
    );
    _email = EmailProvidersCubit(
      widget.dependencies.email,
      allowed: identity.allows(IdentityPermission.manageEmail),
      canImport:
          identity.allows(IdentityPermission.uploadDocuments) &&
          identity.allows(IdentityPermission.readDocuments),
    );
    _activity = PersonalActivityCubit(widget.dependencies.activity);
    _activity.setActive(!identity.mustChangePassword);
    _processing = DocumentProcessingCubit(
      widget.dependencies.processing,
      canReadJobs: identity.allows(IdentityPermission.readDocumentJobs),
      canReindex: identity.allows(IdentityPermission.reindexDocuments),
    );
    _processingSettings = DocumentProcessingSettingsCubit(
      widget.dependencies.processing,
      widget.dependencies.externalLinks,
      allowed: identity.allows(IdentityPermission.manageDocumentProcessing),
    );
    _jobActivity = JobActivityCubit(
      processing: widget.dependencies.processing,
      email: widget.dependencies.email,
      paperless: widget.dependencies.paperless,
      canReadJobs: _processing.canReadJobs,
      canReadBatches: _processing.canReadJobs || _processing.canReindex,
      canReadSystemBatches: identity.allows(
        IdentityPermission.manageDocumentProcessing,
      ),
      canReadEmail: _emailJobs.allowed,
      canReadPaperless: _paperlessJobs.allowed,
    );
    _documents = DocumentsCubit(
      widget.dependencies.documents,
      fileSaver: widget.dependencies.documentFileSaver,
      capabilities: DocumentCapabilities(
        read: identity.allows(IdentityPermission.readDocuments),
        search: identity.allows(IdentityPermission.searchDocuments),
        download: identity.allows(IdentityPermission.downloadDocuments),
        readThumbnails: identity.allows(
          IdentityPermission.readDocumentThumbnails,
        ),
        create: identity.allows(IdentityPermission.createDocuments),
        update: identity.allows(IdentityPermission.updateDocuments),
        readOcr: identity.allows(IdentityPermission.readDocumentOcr),
        updateOcr: identity.allows(IdentityPermission.updateDocumentOcr),
        delete: identity.allows(IdentityPermission.deleteDocuments),
        retry: identity.allows(IdentityPermission.retryDocuments),
        unlock: identity.allows(IdentityPermission.unlockDocuments),
      ),
    );
    widget.dependencies.uploads?.onAccepted = () {
      if (mounted && identity.allows(IdentityPermission.readDocuments)) {
        _documents.invalidate();
        _jobActivity.invalidate();
      }
    };
    _account = AccountCubit(
      widget.dependencies.identity,
      identity: identity,
      onSessionEnded: widget.onSessionEnded,
    );
    _libraries = LibrariesCubit(
      widget.dependencies.identity,
      identity: identity,
      onSwitch: widget.onSwitch,
    );
    _systemUsers = SystemUsersCubit(
      widget.dependencies.identity,
      identity: identity,
      onSessionEnded: widget.onSessionEnded,
    );
    _identity = CurrentIdentityCubit(
      widget.dependencies.identity,
      identity,
      onSessionEnded: widget.onSessionEnded,
    );
    _identitySubscription = _identity.stream.listen((identity) {
      _libraries.updateDisplay(identity);
      _account.updateDisplay(identity);
    });
    _realtime = RealtimeCubit(
      widget.dependencies.realtime,
      onSessionEnded: () =>
          widget.onSessionEnded('Your access changed. Please sign in again.'),
    );
    _realtimeSubscription = _realtime.stream.listen(_onRealtime);
    _fallback = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground &&
          !_realtime.state.healthy &&
          !identity.mustChangePassword) {
        _invalidate({
          RealtimeTopic.documents,
          RealtimeTopic.identity,
          RealtimeTopic.members,
          RealtimeTopic.systemUsers,
        });
      }
    });
    _syncProcessing();
    if (!identity.mustChangePassword &&
        identity.allows(IdentityPermission.readDocuments)) {
      unawaited(_documents.load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dependencies.uploads?.onAccepted = null;
    unawaited(
      _releaseScanner(_scannerCubit, _scannerScope).catchError((Object _) {}),
    );
    _fallback?.cancel();
    unawaited(_realtimeSubscription.cancel());
    unawaited(_identitySubscription.cancel());
    unawaited(_realtime.close());
    unawaited(_identity.close());
    unawaited(_chat.close());
    unawaited(_chatSettings.close());
    unawaited(_processing.close());
    unawaited(_jobActivity.close());
    unawaited(_email.close());
    unawaited(_emailJobs.close());
    unawaited(_paperlessJobs.close());
    unawaited(_paperlessSettings.close());
    unawaited(_workloadSettings.close());
    unawaited(_activity.close());
    unawaited(_processingSettings.close());
    unawaited(_documents.close());
    unawaited(_invoices.close());
    unawaited(_licenses.close());
    unawaited(_account.close());
    unawaited(_libraries.close());
    unawaited(_systemUsers.close());
    unawaited(_navigation.close());
    super.dispose();
  }

  List<AppNavigationGroup> get _groups {
    final identity = widget.session.identity;
    return [
      AppNavigationGroup(
        id: 'documents',
        label: 'Documents',
        icon: Icons.description_outlined,
        collapsible: false,
        items: [
          AppNavigationItem(
            id: 'documents',
            label: 'Documents',
            icon: Icons.description_outlined,
            key: Key('documentsNavigation'),
          ),
        ],
      ),
      if (_invoices.allowed)
        AppNavigationGroup(
          id: 'invoices',
          label: 'Invoices',
          icon: Icons.receipt_long_outlined,
          collapsible: false,
          items: [
            AppNavigationItem(
              id: 'invoices',
              label: 'Invoices',
              icon: Icons.receipt_long_outlined,
              key: Key('invoicesNavigation'),
            ),
          ],
        ),
      if (_chat.allowed)
        AppNavigationGroup(
          id: 'chat',
          label: 'AI chat',
          icon: Icons.forum_outlined,
          collapsible: false,
          items: [
            AppNavigationItem(
              id: 'chat',
              label: 'AI chat',
              icon: Icons.forum_outlined,
              key: Key('chatNavigation'),
            ),
          ],
        ),
      if (identity.allows(IdentityPermission.readDocumentJobs) ||
          identity.allows(IdentityPermission.reindexDocuments) ||
          identity.allows(IdentityPermission.manageEmail) ||
          _paperlessJobs.allowed)
        AppNavigationGroup(
          id: 'jobs',
          label: 'Jobs',
          icon: Icons.work_history_outlined,
          collapsible: false,
          items: [
            AppNavigationItem(
              id: 'jobs',
              label: 'Jobs & pipeline',
              icon: Icons.work_history_outlined,
              key: Key('processingNavigation'),
            ),
          ],
        ),
      AppNavigationGroup(
        id: 'user-settings',
        label: 'User settings',
        compactLabel: 'Settings',
        icon: Icons.settings_outlined,
        items: [
          if (widget.serverSettings != null)
            const AppNavigationItem(
              id: 'server',
              label: 'Server',
              icon: Icons.dns_outlined,
              key: Key('serverNavigation'),
            ),
          const AppNavigationItem(
            id: 'libraries',
            label: 'Libraries',
            icon: Icons.folder_copy_outlined,
            key: Key('manageLibraries'),
          ),
          if (identity.allows(IdentityPermission.manageUsers)) ...[
            const AppNavigationItem(
              id: 'members',
              label: 'Members',
              icon: Icons.people_outline_rounded,
              key: Key('manageMembers'),
            ),
            const AppNavigationItem(
              id: 'invitations',
              label: 'Invitations',
              icon: Icons.mark_email_unread_outlined,
              key: Key('manageInvitations'),
            ),
          ],
          if (identity.allows(IdentityPermission.manageEmail))
            const AppNavigationItem(
              id: 'email',
              label: 'Email accounts',
              icon: Icons.mail_outline,
              key: Key('emailNavigation'),
            ),
          if (widget.dependencies.paperless != null &&
              identity.allows(IdentityPermission.importPaperless) &&
              identity.allows(IdentityPermission.readDocuments) &&
              identity.allows(IdentityPermission.uploadDocuments))
            const AppNavigationItem(
              id: 'paperless',
              label: 'Paperless import',
              icon: Icons.download_outlined,
              key: Key('paperlessNavigation'),
            ),
          const AppNavigationItem(
            id: 'password',
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            key: Key('changePassword'),
          ),
          const AppNavigationItem(
            id: 'licenses',
            label: 'Licenses',
            icon: Icons.policy_outlined,
            key: Key('licensesNavigation'),
          ),
        ],
      ),
      if (identity.allows(IdentityPermission.manageSystemUsers) ||
          identity.allows(IdentityPermission.manageDocumentProcessing) ||
          _chatSettings.allowed ||
          _paperlessSettings.allowed ||
          _workloadSettings.allowed)
        AppNavigationGroup(
          id: 'admin-settings',
          label: 'Admin settings',
          compactLabel: 'Admin',
          icon: Icons.admin_panel_settings_outlined,
          items: [
            if (_workloadSettings.allowed)
              const AppNavigationItem(
                id: 'workload-settings',
                label: 'Workload limits',
                icon: Icons.tune_outlined,
                key: Key('manageWorkloads'),
              ),
            if (_chatSettings.allowed)
              const AppNavigationItem(
                id: 'chat-settings',
                label: 'AI chat',
                icon: Icons.forum_outlined,
                key: Key('manageChat'),
              ),
            if (identity.allows(IdentityPermission.manageSystemUsers))
              AppNavigationItem(
                id: 'system-users',
                label: 'System users',
                icon: Icons.manage_accounts_outlined,
                key: Key('manageSystemUsers'),
              ),
            if (identity.allows(IdentityPermission.manageDocumentProcessing))
              const AppNavigationItem(
                id: 'processing-settings',
                label: 'Document processing',
                icon: Icons.account_tree_outlined,
                key: Key('manageDocumentProcessing'),
              ),
            if (_paperlessSettings.allowed)
              const AppNavigationItem(
                id: 'paperless-settings',
                label: 'Paperless retrievals',
                icon: Icons.speed_outlined,
                key: Key('managePaperless'),
              ),
          ],
        ),
    ];
  }

  void _select(String destination) {
    if (!mounted || _coveredRoute) return;
    if (widget.session.identity.mustChangePassword ||
        !_groups
            .expand((group) => group.items)
            .any((item) => item.id == destination)) {
      return;
    }
    if (destination == _destination) return;
    switch (destination) {
      case 'licenses':
        unawaited(_licenses.load());
      case 'libraries':
        unawaited(_libraries.load());
      case 'members':
      case 'invitations':
        _account.clearSaveError();
        unawaited(_account.load());
        unawaited(_account.loadInvitations());
      case 'password':
        _account.clearSaveError();
      case 'system-users':
        unawaited(_systemUsers.load());
    }
    _navigation.select(destination);
    _syncProcessing();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncProcessing();
  }

  void _onRealtime(RealtimeState state) {
    if (!mounted) return;
    _jobActivity.setRealtimeHealthy(state.healthy);
    _invalidate(state.invalidated);
  }

  void _invalidate(Set<RealtimeTopic> topics) {
    _jobActivity.invalidate(topics);
    final identity = widget.session.identity;
    if (topics.contains(RealtimeTopic.documents) &&
        identity.allows(IdentityPermission.readDocuments)) {
      _documents.invalidate();
    }
    if (topics.contains(RealtimeTopic.documents) ||
        topics.contains(RealtimeTopic.processing)) {
      _invoices.invalidate();
    }
    if (topics.contains(RealtimeTopic.processing)) _processing.invalidate();
    if (topics.contains(RealtimeTopic.processingConfiguration)) {
      _processingSettings.invalidate();
    }
    if (topics.contains(RealtimeTopic.email)) {
      _email.invalidate();
      _emailJobs.invalidate();
    }
    if (topics.contains(RealtimeTopic.paperless)) _paperlessJobs.invalidate();
    if (topics.contains(RealtimeTopic.chat)) _chat.invalidate();
    if (topics.contains(RealtimeTopic.activity)) _activity.invalidate();
    if (topics.contains(RealtimeTopic.identity)) {
      _identity.invalidate();
      _libraries.invalidate();
    }
    if (topics.contains(RealtimeTopic.members) &&
        identity.allows(IdentityPermission.manageUsers)) {
      _account.invalidate();
    }
    if (topics.contains(RealtimeTopic.systemUsers) &&
        identity.allows(IdentityPermission.manageSystemUsers)) {
      _systemUsers.invalidate();
    }
  }

  void _syncProcessing() {
    final identity = widget.session.identity;
    final active = _foreground && !identity.mustChangePassword;
    _jobActivity.setActive(active);
    _realtime.setActive(
      active && identity.allows(IdentityPermission.connectRealtime),
    );
    _identity.setActive(active);
    _documents.setActive(
      active,
      collectionVisible: !_coveredRoute && _destination == 'documents',
    );
    _invoices.setActive(active && !_coveredRoute && _destination == 'invoices');
    _chat.setActive(active && !_coveredRoute && _destination == 'chat');
    _chatSettings.setActive(
      active && !_coveredRoute && _destination == 'chat-settings',
    );
    _libraries.setActive(
      active && !_coveredRoute && _destination == 'libraries',
      foreground: active,
    );
    _account.setActive(
      active &&
          !_coveredRoute &&
          (_destination == 'members' || _destination == 'invitations'),
    );
    _systemUsers.setActive(
      active && !_coveredRoute && _destination == 'system-users',
    );
    _email.setActive(_foreground && !_coveredRoute && _destination == 'email');
    _emailJobs.setActive(active && !_coveredRoute && _destination == 'jobs');
    _paperlessJobs.setActive(
      active && !_coveredRoute && _destination == 'jobs',
    );
    _activity.setActive(
      _foreground && !widget.session.identity.mustChangePassword,
    );
    _processing.setActive(
      _foreground && !_coveredRoute && _destination == 'jobs',
    );
    _processingSettings.setActive(
      _foreground && !_coveredRoute && _destination == 'processing-settings',
    );
    _paperlessSettings.setActive(
      _foreground && !_coveredRoute && _destination == 'paperless-settings',
    );
    _workloadSettings.setActive(
      active && !_coveredRoute && _destination == 'workload-settings',
    );
  }

  Future<void> _openJobActivity(JobActivityItem item) async {
    if (!mounted || _coveredRoute) return;
    _processing.clearSelection();
    _emailJobs.clearSelection();
    _paperlessJobs.clearSelection();
    setState(() {
      _activityView++;
      _activityBatches = item.batch != null;
    });
    _select(item.batch?.scope == 'system' ? 'processing-settings' : 'jobs');
    final view = _activityView;
    bool current() =>
        mounted &&
        !_coveredRoute &&
        _destination == 'jobs' &&
        view == _activityView;
    if (item.kind == JobActivityKind.document ||
        item.kind == JobActivityKind.ai ||
        item.kind == JobActivityKind.thumbnail) {
      await _processing.selectJob(item.id);
    } else {
      try {
        if (item.kind == JobActivityKind.email) {
          final run = await widget.dependencies.email.getRun(item.id);
          if (current()) _emailJobs.selectJob(run);
        } else if (item.kind == JobActivityKind.paperless) {
          final run = await widget.dependencies.paperless!.get(item.id);
          if (current()) _paperlessJobs.selectJob(run);
        }
      } on EmailFailure catch (failure) {
        if (mounted && current()) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message)));
        }
      } on PaperlessFailure catch (failure) {
        if (mounted && current()) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message)));
        }
      }
    }
  }

  Future<void> _openProcessingDocument(String id) async {
    if (!mounted ||
        _coveredRoute ||
        !widget.session.identity.allows(IdentityPermission.readDocuments)) {
      return;
    }
    _documentRoute = true;
    _syncProcessing();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DocumentDetailDialog(
          documentId: id,
          cubit: _documents,
          appearanceAction: widget.appearanceAction,
        ),
        fullscreenDialog: true,
      ),
    );
    if (mounted) {
      _documentRoute = false;
      _syncProcessing();
    }
  }

  Future<void> _openActivity(PersonalActivityItem item) async {
    if (!mounted || !item.canOpen) return;
    if (item.namespaceId != widget.session.identity.accountId) {
      final error = await widget.onSwitch(item.namespaceId);
      if (mounted && error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    if (item.documentId case final id?) {
      await _openProcessingDocument(id);
    } else if (item.providerId case final id?) {
      _select('email');
      await _email.select(id);
    } else if (item.batchId != null) {
      _select('jobs');
    }
  }

  Future<void> _openScanner() async {
    final identity = widget.session.identity;
    if (!mounted ||
        _coveredRoute ||
        identity.mustChangePassword ||
        !identity.allows(IdentityPermission.uploadDocuments)) {
      return;
    }
    setState(() => _scannerRoute = true);
    _syncProcessing();
    ScannerScope? scope;
    ScannerCubit? cubit;
    try {
      final factory = widget.dependencies.scanner;
      if (factory == null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Text('Scan document'),
                actions: [?widget.appearanceAction],
              ),
              body: const AppPaperCanvas(
                child: SafeArea(
                  child: AppEmptyState(
                    icon: Icons.no_photography_outlined,
                    title: 'Mobile scanner unavailable',
                    message: 'Document scanning is available in the Domabas Android and iOS apps. Open this library on your phone to scan pages.',
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }
      scope = await factory.open();
      if (!mounted) return;
      setState(() => _scannerScope = scope);
      cubit = ScannerCubit(
        camera: scope.camera,
        repository: scope.repository,
        allowed:
            identity.allows(IdentityPermission.uploadDocuments) &&
            !identity.mustChangePassword,
        onAccepted: () {
          if (mounted && identity.allows(IdentityPermission.readDocuments)) {
            _documents.invalidate();
          }
        },
      );
      _scannerCubit = cubit;
      final scannerCubit = cubit;
      final scannerScope = scope;
      final result = await Navigator.of(context).push<ScannerExit>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ScannerScreen(
            cubit: scannerCubit,
            previewBuilder: scannerScope.previewBuilder,
            canReadDocuments: identity.allows(IdentityPermission.readDocuments),
            appearanceAction: widget.appearanceAction,
          ),
        ),
      );
      if (mounted &&
          result == ScannerExit.checkLibrary &&
          identity.allows(IdentityPermission.readDocuments)) {
        _documents.invalidate();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The scanner could not open. Your saved scan is retained. Please try again.',
            ),
          ),
        );
      }
    } finally {
      try {
        await _releaseScanner(cubit, scope);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The scanner closed, but local cleanup needs another attempt when you reopen it.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          _scannerCubit = null;
          _scannerScope = null;
          setState(() => _scannerRoute = false);
          _syncProcessing();
        }
      }
    }
  }

  Future<void> _releaseScanner(ScannerCubit? cubit, ScannerScope? scope) async {
    try {
      await cubit?.close();
    } finally {
      await scope?.close();
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<WorkspaceCubit, String>(
    bloc: _navigation,
    builder: (context, _) => BlocBuilder<CurrentIdentityCubit, Identity>(
      bloc: _identity,
      builder: (context, _) => _workspace(context),
    ),
  );

  Widget _workspace(BuildContext context) {
    final identity = _identity.state;
    if (identity.mustChangePassword) return _initialPassword(context);
    return PersonalActivityAction(
      cubit: _activity,
      namespaceId: identity.accountId,
      onOpen: _openActivity,
      builder: (context, activity) => RealtimeStatusAction(
        cubit: _realtime,
        builder: (context, realtime) =>
            BlocBuilder<DocumentsCubit, DocumentsState>(
              bloc: _documents,
              builder: (context, documents) {
                Widget shell(bool uploadsUsable) => _shell(
                  context,
                  identity,
                  activity,
                  realtime,
                  documents,
                  uploadsUsable,
                );
                final uploads = widget.dependencies.uploads;
                return uploads == null
                    ? shell(false)
                    : BlocBuilder<DocumentUploadsCubit, DocumentUploadsState>(
                        bloc: uploads,
                        builder: (context, state) => shell(state.usable),
                      );
              },
            ),
      ),
    );
  }

  bool get _canAct =>
      mounted && ModalRoute.of(context)?.isCurrent == true && !_coveredRoute;

  Widget _shell(
    BuildContext context,
    Identity identity,
    AppWorkspaceAction activity,
    AppWorkspaceAction realtime,
    DocumentsState documents,
    bool uploadsUsable,
  ) {
    return PopScope(
      canPop: _destination == 'documents',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select('documents');
      },
      child: AppWorkspaceShell(
        mobilePrimaryGroupIds: const ['invoices', 'jobs', 'documents', 'chat'],
        activityIndicator: JobActivityIndicator(
          cubit: _jobActivity,
          uploads: widget.dependencies.uploads,
          onOpen: _openJobActivity,
          onSelectFiles: widget.onUpload,
        ),
        selectedId: _destination,
        onSelected: _select,
        libraryPicker: LibrarySwitcher(
          cubit: _libraries,
          contextLabel: _destination == 'documents'
              ? 'Documents'
              : 'Current library',
        ),
        utilityActions: [?widget.appearanceWorkspaceAction, realtime, activity],
        actions: [
          if (_destination == 'documents' &&
              identity.allows(IdentityPermission.uploadDocuments) &&
              widget.onUpload != null &&
              widget.dependencies.uploads != null)
            AppWorkspaceAction(
              id: 'uploadFiles',
              label: 'Upload files',
              icon: Icons.upload_file,
              onPressed: uploadsUsable
                  ? () async {
                      if (_canAct) widget.onUpload?.call();
                    }
                  : null,
            ),
          if (_destination == 'documents' &&
              identity.allows(IdentityPermission.uploadDocuments))
            AppWorkspaceAction(
              id: 'scanDocument',
              label: 'Scan document',
              icon: Icons.document_scanner_outlined,
              onPressed: _coveredRoute
                  ? null
                  : () async {
                      if (_canAct) await _openScanner();
                    },
            ),
          if (_destination == 'documents' &&
              identity.allows(IdentityPermission.readDocuments) &&
              identity.allows(IdentityPermission.createDocuments))
            AppWorkspaceAction(
              id: 'newDocument',
              label: 'Create metadata',
              icon: Icons.note_add_outlined,
              onPressed: documents.isSaving
                  ? null
                  : () async {
                      if (_canAct) {
                        await DocumentCreateAction.open(context, _documents);
                      }
                    },
            ),
          if (identity.allows(IdentityPermission.uploadDocuments))
            if (widget.dependencies.uploads case final uploads?)
              AppWorkspaceAction(
                id: 'viewUploads',
                label: 'View uploads',
                icon: Icons.receipt_long_outlined,
                onPressed: () async {
                  if (_canAct) {
                    await showJobActivity(
                      context,
                      cubit: _jobActivity,
                      uploads: uploads,
                      onOpen: _openJobActivity,
                      onSelectFiles: widget.onUpload,
                    );
                  }
                },
              ),
        ],
        accountLabel: identity.email,
        onLogout: widget.onLogout,
        groups: _groups,
        child: Column(
          children: [
            if (_scannerRoute && _scannerScope == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  liveRegion: true,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppStripedProgressIndicator(
                        semanticsLabel: 'Opening scanner',
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Opening scanner… Finishing any previous scan first.',
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: switch (_destination) {
                'licenses' => LicensesScreen(cubit: _licenses),
                'invoices' => InvoicesScreen(
                  cubit: _invoices,
                  onOpenDocument:
                      identity.allows(IdentityPermission.readDocuments)
                      ? _openProcessingDocument
                      : null,
                ),
                'server' => widget.serverSettings!,
                'email' => EmailProvidersScreen(cubit: _email),
                'paperless' => PaperlessImportScreen(
                  updates: _realtime.stream
                      .where(
                        (state) =>
                            state.invalidated.contains(RealtimeTopic.paperless),
                      )
                      .map((_) {}),
                  repository: widget.dependencies.paperless!,
                  libraryName: identity.accountName,
                ),
                'libraries' => LibrariesScreen(cubit: _libraries),
                'members' => MembersScreen(
                  cubit: _account,
                  copyInvitation: _invitationClipboard.copy,
                ),
                'invitations' => MembersScreen(
                  cubit: _account,
                  invitations: true,
                  copyInvitation: _invitationClipboard.copy,
                ),
                'password' => _passwordSettings(),
                'system-users' => SystemUsersScreen(cubit: _systemUsers),
                'jobs' => BlocBuilder<EmailJobsCubit, EmailJobsState>(
                  bloc: _emailJobs,
                  builder: (context, emailJobs) =>
                      BlocBuilder<PaperlessJobsCubit, PaperlessJobsState>(
                        bloc: _paperlessJobs,
                        builder: (context, paperlessJobs) =>
                            DocumentProcessingScreen(
                              key: ValueKey('activity-view-$_activityView'),
                              initialBatches: _activityBatches,
                              cubit: _processing,
                              onEditExtraction:
                                  identity.allows(
                                    IdentityPermission.manageDocumentProcessing,
                                  )
                                  ? () => _select('processing-settings')
                                  : null,
                              sourcePipeline:
                                  !_emailJobs.allowed && !_paperlessJobs.allowed
                                  ? null
                                  : Column(
                                      children: [
                                        if (_emailJobs.allowed)
                                          const EmailPipeline(),
                                        if (_emailJobs.allowed &&
                                            _paperlessJobs.allowed)
                                          const SizedBox(height: 20),
                                        if (_paperlessJobs.allowed)
                                          const PaperlessPipeline(),
                                      ],
                                    ),
                              jobsList: ProcessingJobsList(
                                documents: _processing,
                                email: _emailJobs,
                                paperless: _paperlessJobs,
                                onOpenEmailJob: _emailJobs.selectJob,
                              ),
                              selectedSourceId:
                                  paperlessJobs.selected?.id ??
                                  emailJobs.selected?.id,
                              selectedSourceTitle:
                                  paperlessJobs.selected != null
                                  ? 'Paperless import'
                                  : emailJobs.selected == null
                                  ? null
                                  : emailJobs.providers
                                            .where(
                                              (provider) =>
                                                  provider.id ==
                                                  emailJobs
                                                      .selected!
                                                      .providerId,
                                            )
                                            .firstOrNull
                                            ?.label ??
                                        'Email import',
                              selectedSourceDetails:
                                  paperlessJobs.selected != null
                                  ? PaperlessJobDetails(
                                      repository:
                                          widget.dependencies.paperless!,
                                      run: paperlessJobs.selected!,
                                      error: paperlessJobs.error,
                                      onOpenImport: () => _select('paperless'),
                                      onOpenDocument: _openProcessingDocument,
                                    )
                                  : emailJobs.selected == null
                                  ? null
                                  : EmailJobDetails(
                                      run: emailJobs.selected!,
                                      error: emailJobs.error,
                                      provider: emailJobs.providers
                                          .where(
                                            (provider) =>
                                                provider.id ==
                                                emailJobs.selected!.providerId,
                                          )
                                          .firstOrNull,
                                      onOpenAccount: (id) {
                                        _select('email');
                                        unawaited(_email.select(id));
                                      },
                                    ),
                              onClearSourceSelection: () {
                                _emailJobs.clearSelection();
                                _paperlessJobs.clearSelection();
                              },
                              onRefresh: () => unawaited(
                                Future.wait([
                                  if (identity.allows(
                                        IdentityPermission.readDocumentJobs,
                                      ) ||
                                      identity.allows(
                                        IdentityPermission.reindexDocuments,
                                      ))
                                    _processing.load(),
                                  if (identity.allows(
                                    IdentityPermission.manageEmail,
                                  ))
                                    _emailJobs.load(),
                                  if (_paperlessJobs.allowed)
                                    _paperlessJobs.load(),
                                ]),
                              ),
                              canReadDocuments: identity.allows(
                                IdentityPermission.readDocuments,
                              ),
                              onOpenDocument: _openProcessingDocument,
                            ),
                      ),
                ),
                'processing-settings' => DocumentProcessingSettingsScreen(
                  cubit: _processingSettings,
                ),
                'chat' => ChatScreen(
                  cubit: _chat,
                  libraryName: identity.accountName,
                  onOpenDocument:
                      identity.allows(IdentityPermission.readDocuments)
                      ? _openProcessingDocument
                      : null,
                ),
                'chat-settings' => ChatSettingsScreen(cubit: _chatSettings),
                'paperless-settings' => PaperlessSettingsScreen(
                  cubit: _paperlessSettings,
                ),
                'workload-settings' => WorkloadSettingsScreen(
                  cubit: _workloadSettings,
                ),
                _ =>
                  identity.allows(IdentityPermission.readDocuments)
                      ? DocumentsScreen(
                          vocabulary: widget.dependencies.vocabulary,
                          appearanceAction: widget.appearanceAction,
                          cubit: _documents,
                          canCreate: identity.allows(
                            IdentityPermission.createDocuments,
                          ),
                        )
                      : const AppPage(
                          title: 'Documents',
                          child: AppEmptyState(
                            icon: Icons.lock_outline,
                            title: 'Library access is limited',
                            message: 'Ask a library manager for permission to view documents.',
                          ),
                        ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordSettings() => Builder(
    builder: (context) => AppPage(
      insetBody: false,
      eyebrow: 'USER SETTINGS',
      title: 'Password',
      description: 'Keep your account secure with a password only you know.',
      child: SingleChildScrollView(
        padding: AppLayout.cardListPadding(context),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeader(
                      title: 'Change password',
                      description: 'You will sign in again after saving.',
                    ),
                    const SizedBox(height: 24),
                    PasswordForm(cubit: _account),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _initialPassword(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Change initial password'),
      actions: [
        ?widget.serverAction,
        ?widget.appearanceAction,
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child:
              MediaQuery.sizeOf(context).width < 600 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20
              ? IconButton.filledTonal(
                  key: const Key('logout'),
                  tooltip: 'Sign out',
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                )
              : OutlinedButton.icon(
                  key: const Key('logout'),
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
        ),
      ],
    ),
    body: AppPaperCanvas(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.session.identity.accountName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(widget.session.identity.email),
                    const SizedBox(height: 20),
                    const Text(
                      'Choose your own password before opening your library.',
                    ),
                    const SizedBox(height: 24),
                    PasswordForm(cubit: _account),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
