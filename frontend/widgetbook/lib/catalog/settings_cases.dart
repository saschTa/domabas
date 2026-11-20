import 'package:domabas/ui/app_presenters.dart';
import 'package:domabas/ui/glacier/glacier_controls.dart';
import 'package:domabas/ui/glacier/glacier_settings.dart';
import 'package:domabas/ui/glacier/glacier_surfaces.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'workload_flow_case.dart';

Widget settingsLeaf(
  String kind, {
  required String parentLabel,
  required String title,
  required VoidCallback onBack,
}) => _SettingsExample(
  kind: kind,
  header: GlacierSettingsHeader(
    parentLabel: parentLabel,
    title: title,
    onBack: onBack,
  ),
);

Widget settingsDialog(
  String kind, {
  Map<String, VoidCallback> menuActions = const {},
  GlacierAppearanceValue? appearanceValue,
  ValueChanged<GlacierAppearanceValue>? onAppearanceChanged,
}) => _SettingsExample(
  kind: kind,
  dialog: true,
  menuActions: menuActions,
  appearanceValue: appearanceValue,
  onAppearanceChanged: onAppearanceChanged,
);

List<CatalogCase> settingsCases() => [
  CatalogCase(
    id: 'settings-record-card',
    domain: 'Identity and settings',
    component: 'Settings composition',
    name: 'Standalone record card',
    widgetType: 'GlacierSettingsRecord',
    builder: (context) => GlacierSettingsPage(
      sections: [
        GlacierSettingsRecord(
          card: true,
          title: 'Household archive',
          detail: 'Documents shared with the people in your household.',
          icon: Icons.folder_shared_outlined,
          status: const AppStatusBadge(label: 'Owner'),
          onTap: () => showGlacierDialog<void>(
            context: context,
            builder: (_) => settingsDialog('members'),
          ),
        ),
        GlacierSettingsRecord(
          card: true,
          title: 'Personal library',
          detail: 'Your private documents and imported email attachments.',
          icon: Icons.folder_outlined,
          actions: [
            GlacierButton(
              label: 'Manage access',
              onPressed: () => showGlacierDialog<void>(
                context: context,
                builder: (_) => settingsDialog('member-edit'),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
  CatalogCase(
    id: 'settings-section-card',
    domain: 'Identity and settings',
    component: 'Settings composition',
    name: 'Section card with validation and actions',
    widgetType: 'GlacierSettingsSection',
    builder: (_) => GlacierSettingsPage(
      sections: [
        GlacierSettingsSection(
          title: 'Email account',
          description: 'Connect an account to collect documents. Only folders you choose are imported into this library.',
          actions: [GlacierButton(label: 'Save account', onPressed: () {})],
          child: const GlacierField(
            label: 'Account name',
            error: 'Enter a name so you can recognize this account.',
          ),
        ),
      ],
    ),
  ),
  CatalogCase(
    id: 'settings-leaf-header',
    domain: 'Identity and settings',
    component: 'Settings composition',
    name: 'Leaf context and return navigation',
    widgetType: 'GlacierSettingsHeader',
    builder: (_) => GlacierSettingsPage(
      header: GlacierSettingsHeader(
        parentLabel: 'Admin settings',
        title: 'Document processing',
        onBack: () {},
      ),
      sections: const [
        GlacierSettingsSection(
          title: 'Processing preferences',
          child: Text('Choose how documents are indexed and analyzed.'),
        ),
      ],
    ),
  ),
  for (final admin in [false, true])
    CatalogCase(
      id: admin ? 'settings-admin-overview' : 'settings-user-overview',
      domain: 'Identity and settings',
      component: 'Settings overview',
      name: admin ? 'Admin settings' : 'User settings',
      widgetType: 'GlacierSettingsOverview',
      builder: (_) => _SettingsOverviewExample(admin: admin),
    ),
  for (final entry in const <(String, String, String, String)>[
    (
      'field-grid',
      'Settings composition',
      'Responsive field pairs',
      'GlacierFieldGrid',
    ),
    (
      'identity-context',
      'Settings composition',
      'Person and library context',
      'GlacierIdentityContext',
    ),
    (
      'permission-group',
      'Settings composition',
      'Inherited permissions',
      'GlacierPermissionGroup',
    ),
    (
      'credential-field',
      'Settings composition',
      'Stored credential and replacement',
      'GlacierCredentialField',
    ),
    ('auth', 'Authentication', 'Sign in', 'GlacierAuthPanel'),
    ('register', 'Authentication', 'Registration', 'GlacierAuthPanel'),
    ('auth-error', 'Authentication', 'Invalid credentials', 'GlacierAuthPanel'),
    ('restore', 'Session', 'Restoration unavailable', 'GlacierRecoveryPanel'),
    ('expired', 'Session', 'Session ended', 'GlacierRecoveryPanel'),
    (
      'switch-unknown',
      'Session',
      'Library switch uncertain',
      'GlacierRecoveryPanel',
    ),
    (
      'signout-error',
      'Session',
      'Offline sign-out failed',
      'GlacierRecoveryPanel',
    ),
    ('password', 'Password', 'Change password', 'GlacierPasswordFields'),
    (
      'initial-password',
      'Password',
      'Initial password',
      'GlacierPasswordFields',
    ),
    (
      'password-error',
      'Password',
      'Confirmation mismatch',
      'GlacierPasswordFields',
    ),
    ('server', 'Server', 'Native connection', 'GlacierServerForm'),
    ('server-error', 'Server', 'Invalid address', 'GlacierServerForm'),
    ('server-hosted', 'Server', 'Hosted browser address', 'GlacierServerForm'),
    (
      'libraries',
      'Libraries',
      'Current and shared libraries',
      'GlacierSettingsRecord',
    ),
    (
      'libraries-empty',
      'Libraries',
      'No library access',
      'GlacierSettingsPage',
    ),
    (
      'libraries-error',
      'Libraries',
      'Page failed with retained records',
      'GlacierSettingsPage',
    ),
    (
      'accept-invitation',
      'Libraries',
      'Accept an invitation',
      'GlacierSettingsPage',
    ),
    ('members', 'Members', 'Members and access', 'GlacierSettingsRecord'),
    (
      'member-edit',
      'Members',
      'Inherited and additional permissions',
      'GlacierMemberEditor',
    ),
    (
      'member-owner',
      'Members',
      'Protected owner access',
      'GlacierMemberEditor',
    ),
    (
      'invitations',
      'Invitations',
      'All invitation outcomes',
      'GlacierSettingsRecord',
    ),
    (
      'invitation-create',
      'Invitations',
      'Create invitation',
      'GlacierMemberEditor',
    ),
    (
      'invitation-code',
      'Invitations',
      'Copy invitation code',
      'GlacierInvitationCode',
    ),
    (
      'users',
      'Administration',
      'System users and protected administrator',
      'GlacierSettingsRecord',
    ),
    (
      'users-unknown',
      'Administration',
      'Administrator count unavailable',
      'GlacierSettingsPage',
    ),
    ('email', 'Email', 'Accounts and import history', 'GlacierSettingsRecord'),
    (
      'email-edit',
      'Email',
      'Mailbox settings and consent',
      'GlacierEmailAccountForm',
    ),
    (
      'email-consent',
      'Email',
      'Consent renewal required',
      'GlacierEmailAccountForm',
    ),
    (
      'paperless',
      'Paperless',
      'Import and retrieval receipts',
      'GlacierSettingsPage',
    ),
    ('retrievals', 'Paperless', 'Retrieval settings', 'GlacierSettingsPage'),
    (
      'chat-settings',
      'AI settings',
      'Chat configuration',
      'GlacierModelConnection',
    ),
    (
      'external-model',
      'AI settings',
      'External provider and credential removal',
      'GlacierModelConnection',
    ),
    (
      'processing',
      'Processing settings',
      'OCR and pipeline readiness',
      'GlacierSettingsPage',
    ),
    (
      'extraction',
      'Processing settings',
      'Separate AI extraction controls',
      'GlacierModelConnection',
    ),
    (
      'workload',
      'Workload',
      'Pipeline and resource load',
      'GlacierWorkloadResource',
    ),
    (
      'settings-conflict',
      'Save recovery',
      'Changed elsewhere with retained draft',
      'GlacierSettingsPage',
    ),
    (
      'settings-uncertain',
      'Save recovery',
      'Unknown save outcome',
      'GlacierSettingsPage',
    ),
    (
      'appearance',
      'Appearance',
      'Theme and activity background',
      'GlacierAppearancePreferences',
    ),
    (
      'appearance-error',
      'Appearance',
      'Preference storage failure',
      'GlacierAppearancePreferences',
    ),
    (
      'licenses',
      'Licenses',
      'Search and continuation',
      'GlacierSettingsRecord',
    ),
    (
      'license-reader',
      'Licenses',
      'Selectable offline notice',
      'GlacierLicenseReader',
    ),
    ('account', 'Account', 'Account utility menu', 'GlacierAccountMenu'),
    (
      'connection',
      'Live updates',
      'Disconnected with retained data',
      'GlacierRecoveryPanel',
    ),
  ])
    CatalogCase(
      id: 'settings-${entry.$1}',
      domain: 'Identity and settings',
      component: entry.$2,
      name: entry.$3,
      widgetType: entry.$4,
      description: 'Fictional local example. No account, server, secret or configuration is changed.',
      builder: (_) => _SettingsExample(kind: entry.$1),
    ),
  for (final phone in [false, true])
    CatalogCase(
      id: phone ? 'settings-workload-flow-phone' : 'settings-workload-flow',
      domain: 'Identity and settings',
      component: 'Workload',
      name: phone ? 'Live resource flow · phone' : 'Live resource flow',
      widgetType: 'GlacierWorkloadFlow',
      builder: (_) => WorkloadFlowExample(phone: phone),
    ),
  CatalogCase(
    id: 'settings-capacity-meter',
    domain: 'Identity and settings',
    component: 'Workload',
    name: 'Capacity states',
    widgetType: 'GlacierCapacityMeter',
    description: 'Idle, busy, saturated and draining resource slots.',
    builder: (_) => const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlacierCapacityMeter(active: 0, limit: 4),
          SizedBox(height: 24),
          GlacierCapacityMeter(active: 2, limit: 4),
          SizedBox(height: 24),
          GlacierCapacityMeter(active: 4, limit: 4),
          SizedBox(height: 24),
          GlacierCapacityMeter(active: 5, limit: 4),
        ],
      ),
    ),
  ),
  for (final kind in [
    'appearance',
    'libraries',
    'account',
    'member-edit',
    'invitation-create',
    'email-edit',
  ])
    CatalogCase(
      id: 'settings-dialog-$kind',
      domain: 'Identity and settings',
      component: 'Glass dialogs',
      name: kind,
      widgetType: 'GlacierDialog',
      description: 'Open the settings dialog above a retained workspace.',
      builder: (context) => GlacierActivityBackdrop(
        values: const [.2, .3, .6, .45, .7, .55, .9],
        child: Center(
          child: GlacierButton(
            label: 'Open ${kind.replaceAll('-', ' ')}',
            onPressed: () => showGlacierDialog<void>(
              context: context,
              builder: (_) => settingsDialog(kind),
            ),
          ),
        ),
      ),
    ),
];

class _SettingsExample extends StatefulWidget {
  const _SettingsExample({
    required this.kind,
    this.dialog = false,
    this.menuActions = const {},
    this.appearanceValue,
    this.onAppearanceChanged,
    this.header,
  });
  final String kind;
  final bool dialog;
  final Map<String, VoidCallback> menuActions;
  final GlacierAppearanceValue? appearanceValue;
  final ValueChanged<GlacierAppearanceValue>? onAppearanceChanged;
  final Widget? header;
  @override
  State<_SettingsExample> createState() => _SettingsExampleState();
}

class _SettingsExampleState extends State<_SettingsExample> {
  final Map<String, TextEditingController> fields = {};
  final workload = SampleWorkload();
  final Map<String, bool> choices = {};
  String? message;
  String role = 'Viewer',
      mode = 'system',
      background = 'activity',
      pattern = 'line';
  double softness = 35;
  bool reduceTransparency = false, removeStored = false;
  int page = 1;

  @override
  void initState() {
    super.initState();
    final appearance = widget.appearanceValue;
    if (appearance != null) {
      mode = appearance.mode;
      background = appearance.background;
      pattern = appearance.pattern;
      softness = appearance.softness;
      reduceTransparency = appearance.reduceTransparency;
    }
  }

  void changeAppearance(VoidCallback change) {
    setState(change);
    widget.onAppearanceChanged?.call(
      GlacierAppearanceValue(
        mode: mode,
        background: background,
        pattern: pattern,
        softness: softness,
        reduceTransparency: reduceTransparency,
      ),
    );
  }

  TextEditingController controller(String id, [String initial = '']) =>
      fields.putIfAbsent(id, () => TextEditingController(text: initial));
  void tell(String value) => setState(() => message = value);
  Widget field(String label, [String initial = '', String? helper]) =>
      GlacierField(
        label: label,
        controller: controller(label, initial),
        helper: helper,
      );
  Widget choice(
    String label, {
    String? description,
    bool selected = false,
    bool disabled = false,
  }) => GlacierChoice(
    label: label,
    description: description,
    selected: choices[label] ?? selected,
    onChanged: disabled
        ? null
        : (value) => setState(() => choices[label] = value ?? false),
  );
  Widget button(
    String label, {
    bool primary = false,
    bool disabled = false,
    IconData? icon,
    String? feedback,
  }) => GlacierButton(
    label: label,
    icon: icon,
    kind: primary ? GlacierButtonKind.primary : GlacierButtonKind.secondary,
    onPressed: disabled
        ? null
        : () {
            if (label == 'Cancel' && widget.dialog) {
              Navigator.of(context).pop();
              return;
            }
            final target = switch (label) {
              'Manage access' => 'member-edit',
              'Invite member' || 'Create invitation'
                  when widget.kind == 'members' ||
                      widget.kind == 'invitations' =>
                'invitation-create',
              'Accept an invitation' => 'accept-invitation',
              'Edit account' || 'Add email account' => 'email-edit',
              'Read license' => 'license-reader',
              'Change password' when widget.kind == 'account' => 'password',
              'Switch library' when widget.kind == 'account' => 'libraries',
              'Appearance and background' => 'appearance',
              _ => null,
            };
            if (target != null) {
              showGlacierDialog<void>(
                context: context,
                builder: (_) => settingsDialog(target),
              );
            } else {
              tell(feedback ?? '$label completed in this local example.');
            }
          },
  );
  Widget section(String title, Widget child, [String? description]) =>
      const [
        'Library members',
        'Your libraries',
        'Invitations',
        'Email accounts',
        'Password',
        'System users',
        'Third-party licenses',
      ].contains(title)
      ? child
      : GlacierSection(title: title, description: description, child: child);
  Widget stack(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final child in children)
        Padding(
          padding: EdgeInsets.only(
            bottom: child is GlacierSettingsRecord ? 0 : 16,
          ),
          child: child,
        ),
    ],
  );
  Widget badge(String label, [AppTone tone = AppTone.neutral]) =>
      AppStatusBadge(label: label, tone: tone);
  Widget record(
    String title,
    String detail, {
    String? status,
    IconData? icon,
    List<Widget> actions = const [],
  }) => GlacierSettingsRecord(
    title: title,
    detail: detail,
    status: status == null ? null : badge(status),
    icon: icon,
    actions: actions,
  );
  Widget pager() => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final count = widget.kind == 'members' ? 2 : 3;
        final label = Text(
          '${widget.kind == 'members' ? '4 sample records · ' : ''}Page $page of $count',
          style: Theme.of(context).textTheme.bodySmall,
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GlacierButton(
              label: 'Previous',
              onPressed: page == 1 ? null : () => setState(() => page--),
            ),
            GlacierButton(
              label: 'Next',
              onPressed: page == count ? null : () => setState(() => page++),
            ),
          ],
        );
        return constraints.maxWidth < 460
            ? Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [label, actions],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  actions,
                ],
              );
      },
    ),
  );
  Widget pageLayout(
    List<Widget> sections, {
    bool save = false,
    List<Widget> actions = const [],
  }) {
    final controls = [
      ...actions,
      if (save) ...[
        button(
          'Use saved values',
          feedback: 'Saved values restored in this local example.',
        ),
        button(
          'Save changes',
          primary: true,
          feedback: 'Changes saved in this local example.',
        ),
      ],
    ];
    if (widget.dialog) {
      final title = switch (widget.kind) {
        'appearance' || 'appearance-error' => 'Appearance and background',
        'libraries' => 'Choose a library',
        'account' => 'Your account',
        'member-edit' || 'member-owner' => 'Manage library access',
        'invitation-create' => 'Invite someone',
        'accept-invitation' => 'Accept an invitation',
        'email-edit' || 'email-consent' => 'Email account',
        'password' => 'Change password',
        'license-reader' => 'License notice',
        _ => 'Library settings',
      };
      return GlacierDialog(
        title: title,
        width:
            [
              'member-edit',
              'member-owner',
              'email-edit',
              'email-consent',
            ].contains(widget.kind)
            ? 820
            : 620,
        actions: controls.isEmpty
            ? [
                GlacierButton(
                  label: 'Back to the workspace',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]
            : controls,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null) ...[
              AppNotice(message: message!),
              const SizedBox(height: 16),
            ],
            ...sections,
          ],
        ),
      );
    }
    return GlacierSettingsPage(
      feedback: message == null ? null : AppNotice(message: message!),
      sections: [
        for (final section in sections)
          if (section is GlacierWorkloadResource || section is AppNotice)
            section
          else
            GlacierSettingsSection(child: section),
      ],
      actions: controls,
    );
  }

  Widget identity() => const GlacierIdentityContext(
    name: 'Alex Morgan',
    email: 'alex@example.test',
    scope: 'Personal library · Library owner',
  );

  Widget dropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> onChanged, {
    bool disabled = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium,
        items: [
          for (final item in items)
            DropdownMenuItem(value: item, child: Text(item)),
        ],
        onChanged: disabled
            ? null
            : (next) {
                if (next != null) onChanged(next);
              },
      ),
    ],
  );

  Widget permissions({bool owner = false}) => GlacierMemberEditor(
    identity: widget.kind == 'invitation-create'
        ? field('Recipient email', 'robin@example.test')
        : GlacierIdentityContext(
            name: owner ? 'Alex Morgan' : 'Sam Chen',
            email: owner ? 'alex@example.test' : 'sam@example.test',
            scope: 'Personal library',
          ),
    roleField: dropdown(
      'Library role',
      owner ? 'Owner' : role,
      owner ? ['Owner'] : ['Viewer', 'User', 'Manager'],
      (value) => setState(() => role = value),
      disabled: owner,
    ),
    notice: AppNotice(
      message: owner
          ? 'Ownership gives full library access. Ownership cannot be changed here.'
          : 'Role permissions stay selected. Saving changes ends this member’s sessions in this library.',
      tone: AppTone.info,
    ),
    permissionGroups: [
      GlacierPermissionGroup(
        title: 'Documents',
        enabled: !owner,
        permissions: [
          const GlacierPermission(
            id: 'read',
            label: 'Read documents',
            inherited: true,
          ),
          GlacierPermission(
            id: 'upload',
            label: 'Upload documents',
            inherited: role != 'Viewer',
            selected: choices['upload'] ?? false,
            description: 'Add originals to this library.',
          ),
          GlacierPermission(
            id: 'delete',
            label: 'Delete documents',
            inherited: role == 'Manager',
            selected: choices['delete'] ?? false,
            description: 'Remove originals and extracted data.',
          ),
        ],
        onChanged: (id, selected) => setState(() => choices[id] = selected),
      ),
      GlacierPermissionGroup(
        title: 'Library access',
        enabled: !owner,
        permissions: [
          GlacierPermission(
            id: 'invite',
            label: 'Manage invitations',
            inherited: role == 'Manager',
            selected: choices['invite'] ?? false,
          ),
        ],
        onChanged: (id, selected) => setState(() => choices[id] = selected),
      ),
    ],
    accessControl: choice(
      'Library access enabled',
      selected: true,
      disabled: owner,
      description: 'Separate from installation administrator rights.',
    ),
  );

  Widget model() => GlacierModelConnection(
    endpointField: field('API base URL', 'https://ai.example.test/v1'),
    modelField: field('Model', 'example-model'),
    credentialField: GlacierCredentialField(
      label: 'API key',
      controller: controller('API key'),
      configured: true,
      removeStored: removeStored,
      onRemoveChanged: (value) => setState(() => removeStored = value),
    ),
    compatibilityControl: choice('LM Studio compatibility mode'),
  );

  @override
  void dispose() {
    for (final value in fields.values) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dialog) {
      final content = buildContent(context);
      return content is GlacierDialog
          ? content
          : GlacierDialog(
              title: widget.kind == 'connection'
                  ? 'Live updates'
                  : 'Your account',
              actions: [
                GlacierButton(
                  label: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
              child: content,
            );
    }
    final title = const {
      'server-hosted': 'Server',
      'server': 'Server',
      'libraries': 'Libraries',
      'members': 'Members',
      'invitations': 'Invitations',
      'email': 'Email accounts',
      'paperless': 'Paperless import',
      'password': 'Password',
      'appearance': 'Appearance',
      'licenses': 'Licenses',
      'workload': 'Workload limits',
      'chat-settings': 'AI chat',
      'users': 'System users',
      'processing': 'Document processing',
      'retrievals': 'Paperless retrievals',
    }[widget.kind];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: title == null && widget.header == null
          ? buildContent(context)
          : Column(
              children: [
                GlacierToolbar(
                  children: [
                    if (widget.header != null)
                      widget.header!
                    else ...[
                      Text(
                        title!,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        [
                              'workload',
                              'chat-settings',
                              'users',
                              'processing',
                              'retrievals',
                            ].contains(widget.kind)
                            ? 'System administrator access'
                            : 'Settings for your account and selected library',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
                Expanded(child: buildContent(context)),
              ],
            ),
    );
  }

  Widget buildContent(BuildContext context) {
    final kind = widget.kind;
    if (kind == 'field-grid') {
      return pageLayout([
        GlacierFieldGrid(
          children: [
            field('Sender name', 'Alex Morgan'),
            field('Contact email', 'alex@example.test'),
            field('Library name', 'Household archive'),
          ],
        ),
      ]);
    }
    if (kind == 'identity-context') {
      return pageLayout([identity()]);
    }
    if (kind == 'permission-group') {
      return pageLayout([
        GlacierPermissionGroup(
          title: 'Documents',
          permissions: [
            const GlacierPermission(
              id: 'read',
              label: 'Read documents',
              inherited: true,
            ),
            GlacierPermission(
              id: 'upload',
              label: 'Upload documents',
              selected: choices['upload'] ?? false,
              description: 'Add originals to this library.',
            ),
          ],
          onChanged: (id, value) => setState(() => choices[id] = value),
        ),
      ]);
    }
    if (kind == 'credential-field') {
      return pageLayout([
        GlacierCredentialField(
          label: 'API key',
          controller: controller('API key'),
          configured: true,
          removeStored: removeStored,
          onRemoveChanged: (value) => setState(() => removeStored = value),
        ),
      ], save: true);
    }
    if (['auth', 'register', 'auth-error'].contains(kind)) {
      return GlacierAuthPanel(
        title: kind == 'register'
            ? 'Create your account'
            : 'Sign in to Domabas',
        description: 'Your private document library.',
        feedback: message != null
            ? AppNotice(message: message!)
            : kind == 'auth-error'
            ? const AppNotice(
                message: 'Email or password is incorrect. Check your details and try again.',
                tone: AppTone.danger,
              )
            : null,
        fields: [
          if (kind == 'register') field('Account name', 'Alex Morgan'),
          field('Email', 'alex@example.test'),
          GlacierField(
            label: 'Password',
            controller: controller('Password'),
            obscureText: true,
          ),
        ],
        submit: button(
          kind == 'register' ? 'Create account' : 'Sign in',
          primary: true,
        ),
        secondaryActions: [
          button(kind == 'register' ? 'Sign in instead' : 'Create an account'),
          button('Server'),
          button('Licenses'),
        ],
      );
    }
    if ([
      'restore',
      'expired',
      'switch-unknown',
      'signout-error',
      'connection',
    ].contains(kind)) {
      final copy = switch (kind) {
        'restore' => (
          'Your session could not be restored',
          'Your saved account remains on this device. Check the server connection and retry.',
          'Retry restoration',
        ),
        'expired' => (
          'Your session ended',
          'Sign in again to continue with your library. Unsaved server changes have not been submitted.',
          'Sign in again',
        ),
        'switch-unknown' => (
          'Library switch could not be confirmed',
          'The server may have changed the active library. Sign in again to restore the authoritative workspace.',
          'Sign in again',
        ),
        'signout-error' => (
          'Sign-out could not be completed',
          'The saved session could not be removed from this device. Try again before leaving a shared computer.',
          'Retry sign-out',
        ),
        _ => (
          'Live updates are unavailable',
          'Personal library shows the last recorded state. Reconnection refreshes it without discarding your drafts.',
          'Reconnect',
        ),
      };
      return GlacierRecoveryPanel(
        title: copy.$1,
        message: message ?? copy.$2,
        actions: [
          button(copy.$3, primary: true),
          if (kind == 'restore') button('Sign out'),
        ],
      );
    }
    if (['password', 'password-error', 'initial-password'].contains(kind)) {
      return pageLayout(
        [
          if (kind == 'initial-password')
            const AppNotice(
              message:
                  'Change the initial password before opening your library.',
              tone: AppTone.warning,
            ),
          section(
            'Password',
            GlacierPasswordFields(
              current: controller('Current'),
              password: controller('New'),
              confirmation: controller('Confirmation'),
              error: kind == 'password-error'
                  ? 'The passwords do not match.'
                  : null,
            ),
          ),
        ],
        actions: [
          button(
            'Change password',
            primary: true,
            feedback: 'Password changed in the local example. The application would end sessions on all devices.',
          ),
        ],
      );
    }
    if (kind.startsWith('server')) {
      return pageLayout([
        GlacierServerForm(
          address: controller('Server', 'https://domabas.example.test'),
          hosted: kind == 'server-hosted',
          error: kind == 'server-error'
              ? 'Use a complete http:// or https:// address.'
              : null,
          onConnect: () => tell('Connected to the fictional server.'),
          onReload: () => setState(
            () => controller('Server').text = 'https://domabas.example.test',
          ),
        ),
      ]);
    }
    if (kind == 'libraries-empty') {
      return pageLayout([
        AppEmptyState(
          icon: Icons.folder_shared_outlined,
          title: 'No library access',
          message: 'Accept an invitation to join a library.',
          action: button('Accept an invitation'),
        ),
      ]);
    }
    if (kind == 'libraries' || kind == 'libraries-error') {
      return pageLayout([
        section(
          'Your libraries',
          stack([
            if (kind == 'libraries-error')
              AppNotice(
                message: 'The next page could not be loaded. Your current libraries remain available.',
                action: button('Retry page'),
              ),
            record(
              page == 1 ? 'Personal library' : 'Garden archive',
              'Alex Morgan · Owner',
              status: page == 1 ? 'Current' : 'Shared',
              icon: Icons.folder_outlined,
            ),
            record(
              'Family library',
              'Shared with your household · User',
              icon: Icons.folder_shared_outlined,
              actions: [button('Switch library')],
            ),
            pager(),
          ]),
        ),
        section(
          'Join another library',
          stack([
            const Text(
              'An invitation adds access without changing your current library.',
            ),
            button('Accept an invitation'),
          ]),
        ),
      ]);
    }
    if (kind == 'accept-invitation') {
      return pageLayout(
        [
          section(
            'Accept an invitation',
            stack([
              field('Invitation code', 'SAMPLE-HOUSEHOLD'),
              const Text(
                'Sign in with the email address the invitation was sent to. Expired or revoked codes cannot be accepted.',
              ),
            ]),
          ),
        ],
        actions: [
          button(
            'Accept invitation',
            primary: true,
            feedback:
                'Garden archive added. Your current library is unchanged.',
          ),
        ],
      );
    }
    if (kind == 'members') {
      return pageLayout([
        section(
          'Library members',
          stack([
            const Text('Personal library · Alex Morgan · owner'),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 730,
                child: Text(
                  'A role gives someone a set of abilities. Additional permissions extend that role. Only people with access can see this library.',
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: button('Invite member', primary: true),
            ),
            record(
              'Alex Morgan',
              'alex@example.test',
              status: 'Owner · Active',
              actions: [button('Manage access')],
            ),
            record(
              page == 1 ? 'Sam Chen' : 'Robin Morgan',
              page == 1 ? 'sam@example.test' : 'robin@example.test',
              status: page == 1 ? 'User · Active' : 'Viewer · Disabled',
              actions: [button('Manage access')],
            ),
            record(
              'Jamie Lee',
              'jamie@example.test',
              status: 'Viewer · Active',
              actions: [button('Manage access')],
            ),
            pager(),
          ]),
        ),
      ]);
    }
    if (['member-edit', 'member-owner', 'invitation-create'].contains(kind)) {
      return pageLayout(
        [permissions(owner: kind == 'member-owner')],
        actions: [
          button('Cancel'),
          button(
            kind == 'invitation-create'
                ? 'Create invitation'
                : 'Review access change',
            primary: true,
            disabled: kind == 'member-owner',
          ),
        ],
      );
    }
    if (kind == 'invitations') {
      return pageLayout(
        [
          section(
            'Invitations',
            stack([
              for (final status in [
                'Pending',
                'Expired',
                'Accepted',
                'Revoked',
              ])
                record(
                  '${status.toLowerCase()}@example.test',
                  'Viewer · Expires 23 Nov 2026',
                  status: status,
                  icon: Icons.mail_outline,
                  actions: status == 'Pending'
                      ? [button('Revoke invitation')]
                      : [],
                ),
              pager(),
            ]),
          ),
        ],
        actions: [button('Create invitation', primary: true)],
      );
    }
    if (kind == 'invitation-code') {
      return pageLayout([
        const Text('This code is fictional and does not grant access.'),
        GlacierInvitationCode(
          email: 'robin@example.test',
          library: 'Family library',
          code: 'SAMPLE-HOUSEHOLD',
          expires: '23 Nov 2026',
          copyFeedback: message,
          onCopy: () => tell(
            'Fictional code copied in this example. No clipboard write occurred.',
          ),
        ),
      ]);
    }
    if (kind == 'users' || kind == 'users-unknown') {
      return pageLayout([
        section(
          'System users',
          stack([
            const Text(
              'Installation administration is independent of library ownership.',
            ),
            if (kind == 'users-unknown')
              const AppNotice(
                message: 'Administrator count is unavailable. Role changes are disabled until it can be checked.',
                tone: AppTone.warning,
              ),
            record(
              'alex@example.test',
              'System administrator · Last administrator',
              status: 'Protected',
              actions: [button('Remove administrator', disabled: true)],
            ),
            record(
              'sam@example.test',
              'No system administration rights',
              actions: [
                button('Make administrator', disabled: kind == 'users-unknown'),
              ],
            ),
            pager(),
          ]),
        ),
      ]);
    }
    if (kind == 'email') {
      return pageLayout([
        section(
          'Email accounts',
          stack([
            record(
              'Personal inbox',
              'alex@example.test · INBOX',
              status: 'Automatic import enabled',
              icon: Icons.mail_outline,
              actions: [
                button('Edit account'),
                button('Import now'),
                button('Delete account'),
              ],
            ),
            button('Add email account'),
          ]),
        ),
        section(
          'Import history',
          stack([
            record(
              '16 Nov 2026 · Scheduled retrieval',
              '12 messages checked · 3 originals accepted · 1 duplicate',
              status: 'Completed',
              icon: Icons.inbox_outlined,
            ),
            record(
              '15 Nov 2026 · Manual retrieval',
              'Connection could not be established. Saved originals remain available.',
              status: 'Failed',
              icon: Icons.inbox_outlined,
              actions: [button('View attempt')],
            ),
            pager(),
          ]),
        ),
      ]);
    }
    if (kind == 'email-edit' || kind == 'email-consent') {
      return pageLayout(
        [
          GlacierEmailAccountForm(
            connectionFields: [
              field('Account label', 'Personal inbox'),
              field('IMAP host', 'imap.example.test'),
              field('Port', '993'),
              field('Username', 'alex@example.test'),
              field('Mailbox', 'INBOX'),
            ],
            scheduleFields: [
              field('Check every (minutes)', '15'),
              field('Maximum email age (days)', '30'),
              field('Messages per page', '50'),
            ],
            credentialField: GlacierCredentialField(
              label: 'App password',
              controller: controller('App password'),
              configured: true,
              removeStored: false,
            ),
            enabledControl: choice(
              'Enable automatic import',
              selected: true,
              description:
                  'Continues after sign-out until disabled or deleted.',
            ),
            consentControl: choice(
              'Allow this mailbox to import into Personal library',
              selected: kind != 'email-consent',
              description: 'Renew consent when the source or library changes.',
            ),
            feedback: kind == 'email-consent'
                ? const AppNotice(
                    message: 'Source details changed. Renew consent before automatic import resumes.',
                    tone: AppTone.warning,
                  )
                : null,
            testActions: [
              button('Test connection'),
              button('Check saved account'),
            ],
          ),
        ],
        actions: [
          button('Cancel'),
          button(
            kind == 'email-consent' ? 'Renew consent and save' : 'Save account',
            primary: true,
          ),
        ],
      );
    }
    if (kind == 'paperless') {
      return pageLayout([
        section(
          'Source archive',
          stack([
            field('Paperless server URL', 'https://paperless.example.test'),
            GlacierCredentialField(
              label: 'API token',
              controller: controller('Paperless token'),
              configured: false,
              removeStored: false,
            ),
            button('Start import', primary: true),
          ]),
        ),
        section(
          'Your imports',
          stack([
            record(
              'Paperless archive',
              '5 checked · 3 accepted · 1 duplicate · 1 failed',
              status: 'Partially completed',
              icon: Icons.cloud_download_outlined,
              actions: [button('View document results')],
            ),
            const Text(
              'Retrieved files continue in separate document-ingestion jobs. Retrieval completion is not processing completion.',
            ),
            pager(),
          ]),
        ),
      ]);
    }
    if (kind == 'retrievals') {
      return pageLayout([
        section(
          'Import speed',
          stack([
            field('Parallel retrievals', '2'),
            const Text(
              'Retrievals also need shared worker capacity. Changing this limit affects future admissions.',
            ),
          ]),
        ),
        section(
          'Shared worker capacity',
          const Text('Import runs share workers with other background jobs.'),
        ),
      ], save: true);
    }
    if (['chat-settings', 'external-model'].contains(kind)) {
      return pageLayout([
        section(
          'AI chat',
          stack([
            choice('Enable AI chat', selected: true),
            choice(
              'Enable thinking for chat',
              description: 'Can increase response time.',
            ),
          ]),
        ),
        section('Model connection', model()),
        section('Shared resource limits', button('View workload limits')),
      ], save: true);
    }
    if (kind == 'extraction') {
      return pageLayout([
        section(
          'Invoice extraction',
          stack([
            choice(
              'Enable AI invoice extraction',
              description: 'Structured e-invoice XML is read independently.',
              selected: true,
            ),
            choice('Enable thinking for invoices'),
          ]),
        ),
        section(
          'Property extraction',
          stack([
            choice(
              'Suggest missing document properties',
              description: 'Preserves properties you have already edited.',
            ),
            choice('Enable thinking for properties'),
          ]),
        ),
        section('Shared extraction model', model()),
      ], save: true);
    }
    if (kind == 'processing') {
      return pageLayout([
        section(
          'OCR settings',
          GlacierFieldGrid(
            children: [
              dropdown('OCR language', 'English + German', [
                'English + German',
                'English',
                'German',
              ], (v) => tell('OCR language changed to $v in this example.')),
              dropdown('Page layout', 'Automatic', [
                'Automatic',
                'Single column',
                'Sparse text',
              ], (v) => tell('Page layout changed to $v in this example.')),
            ],
          ),
        ),
        section(
          'Pipeline readiness',
          stack([
            record(
              'Document ingestion',
              'Text extraction and embeddings configured',
              status: 'Ready',
              icon: Icons.description_outlined,
            ),
            record(
              'AI processing',
              'Invoice and property extraction are independently configured',
              status: 'Ready',
              icon: Icons.auto_awesome_outlined,
              actions: [button('Extraction settings')],
            ),
            record(
              'Thumbnail generation',
              'Previews process independently of document AI',
              status: 'Ready',
              icon: Icons.image_outlined,
            ),
          ]),
        ),
        section(
          'Reindex originals',
          stack([
            const Text(
              'Reprocessing retains originals. Choose the library or installation scope explicitly.',
            ),
            button('Reindex library originals'),
            button('View installation reindex requests'),
          ]),
        ),
      ], save: true);
    }
    if (kind == 'workload') {
      TextEditingController limitField(String id) =>
          controller('workload-$id', '${workload.limits[id]}');
      final valid = workload.limits.keys.every(
        (id) => workload.validate(id, limitField(id).text) == null,
      );
      return pageLayout(
        [
          WorkloadFlowPreview(
            sample: workload,
            onLoad: (value) => setState(() => workload.ingestions = value),
          ),
          const AppNotice(
            message: 'Lowering a limit lets active work finish before new work starts.',
            tone: AppTone.info,
          ),
          for (final pipelines in [true, false]) ...[
            Text(
              pipelines ? 'Pipelines' : 'Shared resources',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final id in workload.limits.keys.where(
              (id) => id.startsWith('pipeline:') == pipelines,
            ))
              GlacierWorkloadResource(
                label: workload.label(id),
                description: switch (id) {
                  'worker' =>
                    'One slot per active background job across all pipelines.',
                  'pipeline:document_ingestion' => 'Generate a thumbnail, recognize text and embed the document.',
                  'stage:paperless' =>
                    'Simultaneous downloads before ingestion.',
                  'embedding-runtime' =>
                    'Used by document indexing and semantic search.',
                  'external' => 'Shared by background jobs using the same provider address.',
                  _ => null,
                },
                active: workload.active(id),
                savedLimit: workload.limits[id]!,
                maximumLimit: workload.maximum(id),
                limitField: TextFormField(
                  controller: limitField(id),
                  onChanged: (_) => setState(() {}),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum parallel',
                  ),
                  validator: (value) => workload.validate(id, value ?? ''),
                ),
                notice: id == 'embedding-runtime'
                    ? 'Embedding runtime queue size 8. The maximum is half the configured queue.'
                    : null,
              ),
          ],
        ],
        actions: [
          GlacierButton(
            label: 'Use saved values',
            onPressed: () => setState(() {
              for (final entry in workload.limits.entries) {
                limitField(entry.key).text = '${entry.value}';
              }
              message = 'Saved sample values restored.';
            }),
          ),
          GlacierButton(
            label: 'Save changes',
            kind: GlacierButtonKind.primary,
            onPressed: valid
                ? () => setState(() {
                    workload.limits.updateAll(
                      (id, _) => int.parse(limitField(id).text),
                    );
                    message = 'Sample settings saved. No server configuration changed.';
                  })
                : null,
          ),
        ],
      );
    }
    if (kind == 'settings-conflict' || kind == 'settings-uncertain') {
      return pageLayout(
        [
          AppNotice(
            message: kind == 'settings-conflict'
                ? 'These settings changed elsewhere. Your draft is retained. Compare saved values before submitting again.'
                : 'The save could not be confirmed. Check the saved values before sending another request.',
            tone: AppTone.warning,
            action: button(
              'Check saved values',
              feedback: 'Saved values checked. The draft remains available.',
            ),
          ),
          section('Import speed', field('Parallel retrievals', '3')),
        ],
        actions: [
          button('Use saved values'),
          button('Save changes', primary: true, disabled: true),
        ],
      );
    }
    if (kind.startsWith('appearance')) {
      return pageLayout([
        GlacierAppearancePreferences(
          footer: const AppNotice(
            tone: AppTone.info,
            message: 'Activity is a design experiment. A blurred line or grid sits behind the workspace without adding a chart panel. This catalog uses fictional activity values.',
          ),
          value: GlacierAppearanceValue(
            mode: mode,
            background: background,
            pattern: pattern,
            softness: softness,
            reduceTransparency: reduceTransparency,
          ),
          onModeChanged: (v) => changeAppearance(() => mode = v),
          onBackgroundChanged: (v) => changeAppearance(() => background = v),
          onPatternChanged: (v) => changeAppearance(() => pattern = v),
          onSoftnessChanged: (v) => changeAppearance(() => softness = v),
          onTransparencyChanged: (v) =>
              changeAppearance(() => reduceTransparency = v),
          status: kind == 'appearance-error'
              ? 'Your choice is applied here, but could not be saved on this device.'
              : null,
          onRetry: kind == 'appearance-error'
              ? () => tell('Preference saved in this local example.')
              : null,
        ),
      ]);
    }
    if (kind == 'licenses') {
      return pageLayout([
        section(
          'Third-party licenses',
          stack([
            GlacierField(
              label: 'Search licenses',
              controller: controller('License search'),
              onChanged: (_) => setState(() {}),
            ),
            if ('flutter dm sans'.contains(
              controller('License search').text.toLowerCase(),
            )) ...[
              record(
                'Flutter',
                'Framework · BSD-3-Clause',
                icon: Icons.article_outlined,
                actions: [button('Read license')],
              ),
              record(
                'DM Sans',
                'Interface typeface · SIL Open Font License',
                icon: Icons.text_fields,
                actions: [button('Read license')],
              ),
              pager(),
            ] else
              const AppEmptyState(
                icon: Icons.search_off,
                title: 'No matching licenses',
                message: 'Try a package or license name.',
              ),
          ]),
        ),
      ]);
    }
    if (kind == 'license-reader') {
      return pageLayout([
        const GlacierLicenseReader(
          name: 'Fictional catalog package',
          version: 'Example only · Full production notices remain in the offline license inventory',
          text: 'This fictional notice demonstrates readable, selectable license content.\n\nPermission is granted to inspect this demonstration without connecting to a server.\n\nThe production license reader displays each dependency’s complete original notice and copyright text. This example does not substitute for that inventory.',
        ),
      ]);
    }
    if (kind == 'account') {
      return pageLayout([
        GlacierAccountMenu(
          identity: identity(),
          actions: [
            for (final entry in const [
              ('Switch library', 'libraries'),
              ('Appearance and background', 'appearance'),
              ('Your activity', 'connection'),
              ('Live updates', 'connection'),
              ('Sign out', 'signout-error'),
            ])
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  alignment: Alignment.centerLeft,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                ),
                onPressed:
                    widget.menuActions[entry.$1] ??
                    () => showGlacierDialog<void>(
                      context: context,
                      builder: (_) => settingsDialog(entry.$2),
                    ),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.$1)),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
          ],
        ),
      ]);
    }
    return const SizedBox.shrink();
  }
}

class _SettingsOverviewExample extends StatefulWidget {
  const _SettingsOverviewExample({required this.admin});
  final bool admin;
  @override
  State<_SettingsOverviewExample> createState() =>
      _SettingsOverviewExampleState();
}

class _SettingsOverviewExampleState extends State<_SettingsOverviewExample> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final destinations = widget.admin
        ? const [
            GlacierSettingsDestination(
              id: 'processing',
              label: 'Document processing',
              description: 'Indexing, extraction and analysis preferences.',
              icon: Icons.auto_awesome_outlined,
            ),
            GlacierSettingsDestination(
              id: 'workload',
              label: 'Workload limits',
              description: 'Control how many background jobs run at once.',
              icon: Icons.tune,
            ),
            GlacierSettingsDestination(
              id: 'users',
              label: 'System users',
              description: 'Manage access to this Domabas server.',
              icon: Icons.manage_accounts_outlined,
            ),
          ]
        : const [
            GlacierSettingsDestination(
              id: 'password',
              label: 'Password',
              description: 'Update the password for your account.',
              icon: Icons.key_outlined,
            ),
            GlacierSettingsDestination(
              id: 'libraries',
              label: 'Libraries',
              description: 'Manage your libraries and accept invitations.',
              icon: Icons.folder_shared_outlined,
            ),
            GlacierSettingsDestination(
              id: 'email',
              label: 'Email accounts',
              description:
                  'Connect accounts and choose which folders import documents.',
              icon: Icons.alternate_email,
            ),
            GlacierSettingsDestination(
              id: 'appearance',
              label: 'Appearance',
              description: 'Choose your theme and activity background.',
              icon: Icons.contrast,
            ),
          ];
    if (selected != null) {
      final destination = destinations.firstWhere(
        (item) => item.id == selected,
      );
      return settingsLeaf(
        destination.id,
        parentLabel: widget.admin ? 'Admin settings' : 'User settings',
        title: destination.label,
        onBack: () => setState(() => selected = null),
      );
    }
    return GlacierSettingsOverview(
      destinations: destinations,
      onSelected: (id) => setState(() => selected = id),
    );
  }
}
