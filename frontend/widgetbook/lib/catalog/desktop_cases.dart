import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'documents_cases.dart';
import 'settings_cases.dart';
import 'workflow_cases.dart';
import 'activity_dock_cases.dart';

List<CatalogCase> desktopCases() => [
  for (final entry in const [
    ('desktop-settings-inline', 'settings-password', false),
    ('desktop-admin-inline', 'settings-workload', false),
    ('desktop-settings-rail', 'settings-password', true),
  ])
    CatalogCase(
      id: entry.$1,
      domain: 'Desktop application',
      component: 'Inline settings navigation',
      name: entry.$1 == 'desktop-admin-inline' ? 'Workload limits' : entry.$1,
      widgetType: 'GlacierWorkspace',
      builder: (_) => desktopWorkspace(
        initialSelected: entry.$2,
        initiallyCollapsed: entry.$3,
      ),
    ),
  CatalogCase(
    id: 'desktop-workspace',
    domain: 'Desktop application',
    component: 'Integrated workspace',
    name: 'All domains and utilities',
    widgetType: 'GlacierWorkspace',
    description: 'A local composition of the real library screens. Navigation, dialogs and sample state stay in this catalog; no production account or API is used.',
    builder: (_) => const _DesktopWorkspace(),
  ),
];

Widget desktopWorkspace({
  String initialSelected = 'documents-grid',
  bool initiallyCollapsed = false,
  String? initialDialog,
  ValueChanged<String>? onLibraryChanged,
}) => _DesktopWorkspace(
  initialSelected: initialSelected,
  initiallyCollapsed: initiallyCollapsed,
  initialDialog: initialDialog,
  onLibraryChanged: onLibraryChanged,
);

class _DesktopWorkspace extends StatefulWidget {
  const _DesktopWorkspace({
    this.initialSelected = 'documents-grid',
    this.initiallyCollapsed = false,
    this.initialDialog,
    this.onLibraryChanged,
  });
  final String initialSelected;
  final bool initiallyCollapsed;
  final String? initialDialog;
  final ValueChanged<String>? onLibraryChanged;
  @override
  State<_DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<_DesktopWorkspace> {
  final entries = {
    for (final entry in [
      ...documentsCases(),
      ...workflowCases(),
      ...settingsCases(),
    ])
      entry.id: entry,
  };
  late String selected = widget.initialSelected;
  @override
  void initState() {
    super.initState();
    if (widget.initialDialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          utility(
            (_) => widget.initialDialog == 'reader'
                ? documentReaderDialog(index: 0)
                : documentSearchDialog(),
          );
        }
      });
    }
  }

  String library = 'Personal library';
  String dockMode = Uri.base.queryParameters['dock'] ?? 'multiple';
  final appearance = ValueNotifier<GlacierAppearanceValue?>(null);
  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  ThemeData appearanceTheme(GlacierAppearanceValue? value) {
    if (value == null) return Theme.of(context);
    final dark =
        value.mode == 'dark' ||
        (value.mode == 'system' &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return dark
        ? GlacierTheme.dark(opaque: value.reduceTransparency)
        : GlacierTheme.light(opaque: value.reduceTransparency);
  }

  void openAppearance() => utility(
    (_) => settingsDialog(
      'appearance',
      appearanceValue:
          appearance.value ??
          GlacierAppearanceValue(
            mode: Theme.of(context).brightness == Brightness.dark
                ? 'dark'
                : 'light',
            background: 'atmosphere',
          ),
      onAppearanceChanged: (value) => appearance.value = value,
    ),
  );
  void navigate(String id) => setState(() => selected = id);
  void openDockJob(String id) {
    final job = activityDockSampleJobs(
      dockMode,
      library: library,
    ).firstWhere((job) => job.id == id);
    utility(
      (_) => GlacierDialog(
        title: job.title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppStatusBadge(label: job.status),
            const SizedBox(height: 16),
            Text(job.library ?? 'Library not recorded'),
            const SizedBox(height: 8),
            Text(job.stage ?? 'Current stage not recorded'),
            if (dockMode == 'stale' || dockMode == 'error') ...[
              const SizedBox(height: 12),
              const Text('Last known activity. Updates are unavailable.'),
            ],
            if (job.progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: job.progress),
            ],
          ],
        ),
      ),
    );
  }

  void openActivity() {
    final jobs = activityDockSampleJobs(dockMode, library: library);
    final uncertain = [
      'unknown',
      'stale',
      'error',
      'truncated',
    ].contains(dockMode);
    utility(
      (dialogContext) => GlacierDialog(
        title: 'Your activity',
        child: SizedBox(
          height: 440,
          child: GlacierActivityPanel(
            library: library,
            running: uncertain ? null : jobs.where((job) => job.running).length,
            waiting: uncertain
                ? null
                : jobs.where((job) => job.status == 'Waiting to start').length,
            notice: uncertain
                ? Text(
                    dockMode == 'truncated'
                        ? 'More activity is available beyond these loaded jobs.'
                        : 'Last known activity. Current totals are unavailable.',
                  )
                : null,
            jobs: [
              for (final job in jobs)
                GlacierJobRow(
                  title: job.title,
                  pipeline: job.stage ?? 'Current stage not recorded',
                  timestamp: 'Latest recorded activity',
                  status: job.status,
                  running: job.running,
                  activity: true,
                  onOpen: () {
                    Navigator.pop(dialogContext);
                    openDockJob(job.id);
                  },
                ),
            ],
            reindex: GlacierButton(
              label: 'View reindex requests',
              onPressed: () {
                Navigator.pop(dialogContext);
                navigate('reindex-enumerating');
              },
            ),
            onUploads: () {
              Navigator.pop(dialogContext);
              navigate('document-upload-receipts');
            },
          ),
        ),
      ),
    );
  }

  void utility(WidgetBuilder builder) => showGlacierDialog<void>(
    context: context,
    builder: (_) => ValueListenableBuilder<GlacierAppearanceValue?>(
      valueListenable: appearance,
      builder: (_, value, _) => Theme(
        data: appearanceTheme(value),
        child: Builder(builder: builder),
      ),
    ),
  );

  static const settings = [
    GlacierDestination(
      id: 'settings-server',
      label: 'Server',
      icon: Icons.dns_outlined,
    ),
    GlacierDestination(
      id: 'settings-libraries',
      label: 'Libraries',
      icon: Icons.folder_shared_outlined,
    ),
    GlacierDestination(
      id: 'settings-members',
      label: 'Members',
      icon: Icons.people_outline,
    ),
    GlacierDestination(
      id: 'settings-invitations',
      label: 'Invitations',
      icon: Icons.mail_outline,
    ),
    GlacierDestination(
      id: 'settings-email',
      label: 'Email accounts',
      icon: Icons.alternate_email,
    ),
    GlacierDestination(
      id: 'settings-paperless',
      label: 'Paperless import',
      icon: Icons.cloud_download_outlined,
    ),
    GlacierDestination(
      id: 'settings-password',
      label: 'Password',
      icon: Icons.key_outlined,
    ),
    GlacierDestination(
      id: 'settings-appearance',
      label: 'Appearance',
      icon: Icons.contrast,
    ),
    GlacierDestination(
      id: 'settings-licenses',
      label: 'Licenses',
      icon: Icons.article_outlined,
    ),
  ];
  static const administration = [
    GlacierDestination(
      id: 'settings-workload',
      label: 'Workload limits',
      icon: Icons.tune,
    ),
    GlacierDestination(
      id: 'settings-chat-settings',
      label: 'AI chat',
      icon: Icons.chat_bubble_outline,
    ),
    GlacierDestination(
      id: 'settings-users',
      label: 'System users',
      icon: Icons.manage_accounts_outlined,
    ),
    GlacierDestination(
      id: 'settings-processing',
      label: 'Document processing',
      icon: Icons.auto_awesome_outlined,
    ),
    GlacierDestination(
      id: 'settings-retrievals',
      label: 'Paperless retrievals',
      icon: Icons.download_outlined,
    ),
  ];

  Widget libraryPicker(BuildContext dialogContext) => GlacierDialog(
    title: 'Switch library',
    actions: [
      GlacierButton(
        label: 'Done',
        onPressed: () => Navigator.pop(dialogContext),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in ['Personal library', 'Family library'])
          GlacierSettingsRecord(
            title: name,
            detail: name == 'Personal library'
                ? 'Alex Morgan · Owner'
                : 'Household · Shared library',
            icon: Icons.library_books_outlined,
            status: name == library
                ? const AppStatusBadge(label: 'Current')
                : null,
            actions: name == library
                ? []
                : [
                    GlacierButton(
                      label: 'Switch to $name',
                      onPressed: () {
                        setState(() {
                          library = name;
                          selected = 'documents-grid';
                        });
                        widget.onLibraryChanged?.call(name);
                        Navigator.pop(dialogContext);
                      },
                    ),
                  ],
          ),
      ],
    ),
  );

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<GlacierAppearanceValue?>(
    valueListenable: appearance,
    builder: (_, value, _) => Theme(
      data: appearanceTheme(value),
      child: GlacierWorkspace(
        initiallyCollapsed: widget.initiallyCollapsed,
        brand: Image.asset(
          'packages/domabas/assets/branding/domabas-mark.png',
          excludeFromSemantics: true,
        ),
        selected: selected,
        onSelected: navigate,
        libraryLabel: library,
        accountLabel: 'Alex Morgan',
        activityDock: dockMode == 'zero'
            ? null
            : GlacierActivityDock(
                jobs: activityDockSampleJobs(
                  dockMode,
                  library: library,
                  onOpen: openDockJob,
                ),
                breakdown: '1 running · 1 waiting',
                stale: dockMode == 'stale',
                truncated: dockMode == 'truncated',
                refreshError: dockMode == 'error'
                    ? 'Updates unavailable. Last known jobs remain visible.'
                    : null,
                onRetryRefresh: () => setState(() => dockMode = 'multiple'),
                onDismissReceipt:
                    ['failed', 'partial', 'completed'].contains(dockMode)
                    ? () => setState(() => dockMode = 'zero')
                    : null,
                onOpenActivity: openActivity,
              ),
        onSearch: () => utility(
          (_) =>
              documentSearchDialog(invoice: selected == 'invoice-collection'),
        ),
        onLibrary: () => utility(libraryPicker),
        onActivity: openActivity,
        onAppearance: openAppearance,
        onAccount: () => utility(
          (dialogContext) => settingsDialog(
            'account',
            menuActions: {
              'Appearance and background': () {
                Navigator.pop(dialogContext);
                openAppearance();
              },
              'Switch library': () {
                Navigator.pop(dialogContext);
                utility(libraryPicker);
              },
              'Your activity': () {
                Navigator.pop(dialogContext);
                openActivity();
              },
            },
          ),
        ),
        activityBackground: value?.background == 'activity',
        plainBackground: value?.background == 'plain',
        backgroundGrid: value?.pattern == 'grid',
        backgroundSoftness: (value?.softness ?? 35) / 5,
        backgroundValues: const [
          .2,
          .35,
          .25,
          .7,
          .55,
          .9,
          .75,
          .6,
          .8,
          .65,
          .95,
        ],
        destinations: const [
          GlacierDestination(
            id: 'documents-grid',
            label: 'Documents',
            icon: Icons.description_outlined,
          ),
          GlacierDestination(
            id: 'invoice-collection',
            label: 'Invoices',
            icon: Icons.receipt_long_outlined,
          ),
          GlacierDestination(
            id: 'chat-conversation',
            label: 'AI chat',
            icon: Icons.chat_bubble_outline,
          ),
          GlacierDestination(
            id: 'jobs-history',
            label: 'Jobs',
            icon: Icons.work_outline,
          ),
          GlacierDestination(
            id: 'settings',
            label: 'User settings',
            icon: Icons.settings_outlined,
            children: settings,
          ),
          GlacierDestination(
            id: 'admin',
            label: 'Admin settings',
            icon: Icons.admin_panel_settings_outlined,
            children: administration,
          ),
        ],
        child: KeyedSubtree(
          key: ValueKey('$library/$selected'),
          child: selected == 'settings' || selected == 'admin'
              ? GlacierSettingsOverview(
                  destinations: [
                    for (final item
                        in selected == 'settings' ? settings : administration)
                      GlacierSettingsDestination(
                        id: item.id,
                        label: item.label,
                        description: _description(item.id),
                        icon: item.icon,
                      ),
                  ],
                  onSelected: navigate,
                )
              : settings.any((item) => item.id == selected) ||
                    administration.any((item) => item.id == selected)
              ? settingsLeaf(
                  selected.replaceFirst('settings-', ''),
                  parentLabel: settings.any((item) => item.id == selected)
                      ? 'User settings'
                      : 'Admin settings',
                  title: [
                    ...settings,
                    ...administration,
                  ].firstWhere((item) => item.id == selected).label,
                  onBack: () => navigate(
                    settings.any((item) => item.id == selected)
                        ? 'settings'
                        : 'admin',
                  ),
                )
              : Builder(builder: entries[selected]!.builder),
        ),
      ),
    ),
  );
}

String _description(String id) => switch (id) {
  'settings-server' => 'Manage the connection to your Domabas server.',
  'settings-libraries' => 'Manage libraries and accept invitations.',
  'settings-members' => 'Manage people and their access to this library.',
  'settings-invitations' => 'Invite someone and review pending invitations.',
  'settings-email' =>
    'Connect accounts and import documents from selected folders.',
  'settings-paperless' =>
    'Connect Paperless and import your existing documents.',
  'settings-password' => 'Update the password for your account.',
  'settings-appearance' => 'Choose your theme and activity background.',
  'settings-licenses' => 'Read third-party software licenses.',
  'settings-workload' => 'Control how many background jobs run at once.',
  'settings-chat-settings' => 'Configure models and preferences for AI chat.',
  'settings-users' => 'Manage access to this Domabas server.',
  'settings-processing' =>
    'Configure document indexing, extraction and analysis.',
  'settings-retrievals' => 'Review Paperless retrievals and their progress.',
  _ => '',
};
