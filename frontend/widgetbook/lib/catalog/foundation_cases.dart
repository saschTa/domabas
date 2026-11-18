import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'catalog_frame.dart';

List<CatalogCase> foundationCases() => [
  CatalogCase(
    id: 'foundations-material',
    domain: 'Foundations',
    component: 'Material',
    name: 'Glacier surfaces',
    widgetType: 'GlacierSurface',
    builder: (context) => CatalogFrame(
      child: GlacierSurface(
        child: GlacierSection(
          title: 'Quiet surfaces for your documents',
          description:
              'Mineral glass, clear typography and source-faithful originals.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.onSurface,
              ])
                Container(
                  width: 80,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-buttons',
    domain: 'Foundations',
    component: 'Actions',
    name: 'Hierarchy and busy states',
    widgetType: 'GlacierButton',
    builder: (context) => CatalogFrame(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final kind in GlacierButtonKind.values)
            GlacierButton(
              label: switch (kind) {
                GlacierButtonKind.primary => 'Save changes',
                GlacierButtonKind.secondary => 'Cancel',
                GlacierButtonKind.quiet => 'View details',
                GlacierButtonKind.danger => 'Delete document',
              },
              kind: kind,
              onPressed: () => _message(context, 'Example action activated'),
            ),
          const GlacierButton(label: 'Saving', busy: true, onPressed: null),
          const GlacierButton(label: 'Unavailable', onPressed: null),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-icon-actions',
    domain: 'Foundations',
    component: 'Actions',
    name: 'Named icon controls',
    widgetType: 'GlacierIconButton',
    builder: (context) => CatalogFrame(
      child: Wrap(
        children: [
          GlacierIconButton(
            label: 'Download original',
            icon: Icons.download_outlined,
            onPressed: () => _message(context, 'Example download requested'),
          ),
          const GlacierIconButton(
            label: 'Delete document unavailable',
            icon: Icons.delete_outline,
            onPressed: null,
          ),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-choice',
    domain: 'Foundations',
    component: 'Selection',
    name: 'Rich choice, mixed and inherited',
    widgetType: 'GlacierChoice',
    builder: (context) => const CatalogFrame(child: _SelectionExample()),
  ),
  CatalogCase(
    id: 'foundations-switch',
    domain: 'Foundations',
    component: 'Selection',
    name: 'Switch with explanation',
    widgetType: 'GlacierSwitchRow',
    builder: (context) => const CatalogFrame(child: _SwitchExample()),
  ),
  CatalogCase(
    id: 'foundations-field',
    domain: 'Foundations',
    component: 'Fields',
    name: 'Editable, error and disabled',
    widgetType: 'GlacierField',
    builder: (context) => const CatalogFrame(
      child: Column(
        children: [
          GlacierField(
            label: 'Document title',
            hint: 'Give this document a useful name',
          ),
          SizedBox(height: 24),
          GlacierField(
            label: 'Email address',
            error: 'Enter a complete email address.',
          ),
          SizedBox(height: 24),
          GlacierField(
            label: 'Saved credential',
            obscureText: true,
            enabled: false,
            helper: 'A credential is saved. Choose Replace in the owning form to change it.',
          ),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-tag',
    domain: 'Foundations',
    component: 'Tags',
    name: 'Removable tags',
    widgetType: 'GlacierTag',
    builder: (context) => const CatalogFrame(child: _TagsExample()),
  ),
  CatalogCase(
    id: 'foundations-section',
    domain: 'Foundations',
    component: 'Sections',
    name: 'Label and contextual action',
    widgetType: 'GlacierSection',
    builder: (context) => CatalogFrame(
      child: GlacierSection(
        title: 'Related documents',
        description: 'Originals and attachments connected to this record.',
        trailing: TextButton(
          onPressed: () => _message(context, 'Showing all related records'),
          child: const Text('View all'),
        ),
        child: const Text('Household energy agreement · 3 attachments'),
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-toolbar',
    domain: 'Foundations',
    component: 'Toolbar',
    name: 'Quick controls',
    widgetType: 'GlacierToolbar',
    builder: (context) => CatalogFrame(
      child: GlacierToolbar(
        trailing: [
          GlacierButton(
            label: 'Upload',
            icon: Icons.add,
            kind: GlacierButtonKind.primary,
            onPressed: () =>
                _message(context, 'Choose files in the upload example'),
          ),
        ],
        children: [
          FilterChip(
            label: const Text('All documents'),
            selected: true,
            onSelected: (_) => _message(context, 'All documents selected'),
          ),
          DropdownMenu<String>(
            initialSelection: 'Newest first',
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: 'Newest first', label: 'Newest first'),
              DropdownMenuEntry(value: 'Oldest first', label: 'Oldest first'),
            ],
          ),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-dialog',
    domain: 'Foundations',
    component: 'Dialogs',
    name: 'Scoped confirmation',
    widgetType: 'GlacierDialog',
    builder: (context) => const _DialogExample(),
  ),
  CatalogCase(
    id: 'foundations-empty',
    domain: 'Foundations',
    component: 'Feedback',
    name: 'First document',
    widgetType: 'GlacierEmpty',
    builder: (context) => CatalogFrame(
      child: GlacierEmpty(
        title: 'Your documents, in one place',
        description:
            'Upload a PDF, image or email to start your private library.',
        action: GlacierButton(
          label: 'Upload documents',
          kind: GlacierButtonKind.primary,
          onPressed: () =>
              _message(context, 'Choose files in the upload example'),
        ),
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-notice',
    domain: 'Foundations',
    component: 'Feedback',
    name: 'Recovery notices',
    widgetType: 'AppNotice',
    builder: (context) => CatalogFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tone in AppTone.values) ...[
            AppNotice(
              message: switch (tone) {
                AppTone.neutral => 'Your original file remains unchanged.',
                AppTone.info => 'Search is updating for this document.',
                AppTone.success => 'Your changes are saved.',
                AppTone.warning =>
                  'Live updates paused. Showing the last received data.',
                AppTone.danger =>
                  'Changes could not be saved. Your draft is retained.',
              },
              tone: tone,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-status',
    domain: 'Foundations',
    component: 'Feedback',
    name: 'Status vocabulary',
    widgetType: 'AppStatusBadge',
    builder: (context) => CatalogFrame(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final tone in AppTone.values)
            AppStatusBadge(
              label: switch (tone) {
                AppTone.neutral => 'Not recorded',
                AppTone.info => 'Running',
                AppTone.success => 'Completed',
                AppTone.warning => 'Waiting',
                AppTone.danger => 'Failed',
              },
              tone: tone,
            ),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-pagination',
    domain: 'Foundations',
    component: 'Pagination',
    name: 'Bounded records',
    widgetType: 'AppPagedList',
    builder: (context) => CatalogFrame(
      child: AppPagedList(
        itemCount: 23,
        pageSize: 5,
        itemBuilder: (context, index) => ListTile(
          title: Text('Record ${index + 1}'),
          subtitle: const Text('Fictional collection entry'),
        ),
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-progress',
    domain: 'Foundations',
    component: 'Feedback',
    name: 'Stable progress slot',
    widgetType: 'AppProgressSlot',
    builder: (context) => const CatalogFrame(
      child: Column(
        children: [
          AppProgressSlot(active: true),
          Text('Refreshing while keeping existing results visible'),
          SizedBox(height: 20),
          AppProgressSlot(active: false),
          Text('No layout jump when progress finishes'),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'foundations-refresh',
    domain: 'Foundations',
    component: 'Refresh',
    name: 'Preserve content while refreshing',
    widgetType: 'AppRefreshable',
    builder: (context) => const _RefreshExample(),
  ),
  CatalogCase(
    id: 'foundations-backdrop',
    domain: 'Foundations',
    component: 'Activity backdrop',
    name: 'Abstract caller supplied series',
    widgetType: 'GlacierActivityBackdrop',
    description:
        'Fictional normalized activity; no statistics API is contacted.',
    builder: (context) => const Scaffold(
      body: GlacierActivityBackdrop(
        values: [.1, .2, .15, .4, .35, .62, .5, .7, .68, .85, .75, .95],
        child: Center(
          child: GlacierSurface(
            child: Text(
              'Activity supports the surface without becoming a chart.',
            ),
          ),
        ),
      ),
    ),
  ),
  CatalogCase(
    id: 'workspace-expanded',
    domain: 'Workspace',
    component: 'Shell',
    name: 'Expanded navigation and quick filters',
    widgetType: 'GlacierWorkspace',
    builder: (context) => const _WorkspaceExample(),
  ),
  CatalogCase(
    id: 'workspace-collapsed',
    domain: 'Workspace',
    component: 'Shell',
    name: 'Collapsed utilities hidden',
    widgetType: 'GlacierWorkspace',
    builder: (context) => const _WorkspaceExample(collapsed: true),
  ),
];

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _SelectionExample extends StatefulWidget {
  const _SelectionExample();
  @override
  State<_SelectionExample> createState() => _SelectionExampleState();
}

class _SelectionExampleState extends State<_SelectionExample> {
  bool? value = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      GlacierChoice(
        label: 'Invoices',
        description: 'Include documents with invoice information.',
        selected: value,
        onChanged: (v) => setState(() => value = v),
      ),
      const SizedBox(height: 12),
      const GlacierChoice(
        label: 'Read documents',
        description: 'Included in the selected role',
        selected: true,
        onChanged: null,
      ),
      const SizedBox(height: 12),
      GlacierChoice(
        label: 'Some permissions selected',
        selected: null,
        onChanged: (v) => setState(() => value = v),
      ),
    ],
  );
}

class _SwitchExample extends StatefulWidget {
  const _SwitchExample();
  @override
  State<_SwitchExample> createState() => _SwitchExampleState();
}

class _SwitchExampleState extends State<_SwitchExample> {
  bool value = true;
  @override
  Widget build(BuildContext context) => GlacierSwitchRow(
    label: 'Reduce transparency',
    description: 'Use solid surfaces and hide the activity background.',
    value: value,
    onChanged: (v) => setState(() => value = v),
  );
}

class _TagsExample extends StatefulWidget {
  const _TagsExample();
  @override
  State<_TagsExample> createState() => _TagsExampleState();
}

class _TagsExampleState extends State<_TagsExample> {
  final tags = ['Household', 'Utilities', 'November 2026'];
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (final tag in tags)
        GlacierTag(
          label: tag,
          onDeleted: () => setState(() => tags.remove(tag)),
        ),
    ],
  );
}

class _DialogExample extends StatelessWidget {
  const _DialogExample();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: GlacierButton(
        label: 'Delete document…',
        onPressed: () => showGlacierDialog<void>(
          context: context,
          builder: (context) => GlacierDialog(
            title: 'Delete this document?',
            actions: [
              GlacierButton(
                label: 'Keep document',
                onPressed: () => Navigator.pop(context),
              ),
              GlacierButton(
                label: 'Delete document',
                kind: GlacierButtonKind.danger,
                onPressed: () => Navigator.pop(context),
              ),
            ],
            child: const Text(
              'November electricity · Personal library\n\nThe document, original and extracted information will be removed from this library. This example affects fictional data only.',
            ),
          ),
        ),
      ),
    ),
  );
}

class _RefreshExample extends StatefulWidget {
  const _RefreshExample();
  @override
  State<_RefreshExample> createState() => _RefreshExampleState();
}

class _RefreshExampleState extends State<_RefreshExample> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppRefreshable(
      onRefresh: () async {
        setState(() => count++);
      },
      child: ListView(
        children: [
          ListTile(
            title: const Text('Pull down or press F5 to refresh'),
            subtitle: Text('$count refresh requests in this example'),
          ),
          for (var i = 0; i < 8; i++)
            ListTile(title: Text('Saved record ${i + 1}')),
        ],
      ),
    ),
  );
}

class _WorkspaceExample extends StatefulWidget {
  const _WorkspaceExample({this.collapsed = false});
  final bool collapsed;
  @override
  State<_WorkspaceExample> createState() => _WorkspaceExampleState();
}

class _WorkspaceExampleState extends State<_WorkspaceExample> {
  String selected = 'documents';
  bool tagged = false;
  void panel(String title) {
    showGlacierDialog<void>(
      context: context,
      builder: (context) => GlacierDialog(
        title: title,
        actions: [
          GlacierButton(
            label: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
        child: Text(
          '$title is available from the sidebar. Open its dedicated catalog example to explore the complete interaction.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GlacierWorkspace(
    brand: Image.asset(
      'packages/domabas/assets/branding/domabas-mark.png',
      excludeFromSemantics: true,
    ),
    initiallyCollapsed: widget.collapsed,
    selected: selected,
    onSelected: (id) => setState(() => selected = id),
    onSearch: () => panel('Search'),
    libraryLabel: 'Personal library',
    accountLabel: 'Alex Morgan',
    onLibrary: () => panel('Select library'),
    onActivity: () => panel('Activity'),
    onAppearance: () => panel('Appearance'),
    onAccount: () => panel('Account and utilities'),
    backgroundValues: const [.2, .3, .25, .5, .42, .7, .6, .8, .74, .95],
    destinations: const [
      GlacierDestination(
        id: 'documents',
        label: 'Documents',
        icon: Icons.description_outlined,
      ),
      GlacierDestination(
        id: 'invoices',
        label: 'Invoices',
        icon: Icons.receipt_long_outlined,
      ),
      GlacierDestination(
        id: 'chat',
        label: 'AI chat',
        icon: Icons.chat_bubble_outline,
      ),
      GlacierDestination(id: 'jobs', label: 'Jobs', icon: Icons.work_outline),
      GlacierDestination(
        id: 'settings',
        label: 'Settings',
        icon: Icons.settings_outlined,
        children: [
          GlacierDestination(
            id: 'libraries',
            label: 'Libraries',
            icon: Icons.folder_outlined,
          ),
          GlacierDestination(
            id: 'members',
            label: 'Members',
            icon: Icons.people_outline,
          ),
          GlacierDestination(
            id: 'email',
            label: 'Email accounts',
            icon: Icons.mail_outline,
          ),
        ],
      ),
      GlacierDestination(
        id: 'admin',
        label: 'Administration',
        icon: Icons.admin_panel_settings_outlined,
        children: [
          GlacierDestination(
            id: 'workload',
            label: 'Workload limits',
            icon: Icons.speed,
          ),
        ],
      ),
    ],
    toolbar: GlacierToolbar(
      trailing: [
        GlacierButton(
          label: 'Upload',
          kind: GlacierButtonKind.primary,
          icon: Icons.add,
          onPressed: () => panel('Upload documents'),
        ),
      ],
      children: [
        FilterChip(
          label: const Text('Tagged'),
          selected: tagged,
          onSelected: (v) => setState(() => tagged = v),
        ),
        const Padding(padding: EdgeInsets.all(8), child: Text('Newest first')),
      ],
    ),
    child: ListView(
      children: [
        for (var i = 0; i < (tagged ? 3 : 8); i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlacierSurface(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  [
                    'November electricity',
                    'Home insurance',
                    'Rental agreement',
                  ][i % 3],
                ),
                subtitle: Text('Fictional record · $selected'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => panel('Document reader'),
              ),
            ),
          ),
      ],
    ),
  );
}
