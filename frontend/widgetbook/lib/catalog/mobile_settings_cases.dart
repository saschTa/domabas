import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_case.dart';
import 'mobile_catalog.dart';
import 'workload_flow_case.dart';

const _screens = <(String, String, String, List<String>)>[
  (
    'more',
    'More destinations',
    'GlacierMobileRecordRow',
    ['ready', 'restricted'],
  ),
  (
    'library',
    'Choose library',
    'GlacierMobileLibraryRow',
    ['ready', 'empty', 'error'],
  ),
  (
    'libraries',
    'Libraries',
    'GlacierMobileLibraryRow',
    ['ready', 'create', 'page-error'],
  ),
  (
    'members',
    'Members and roles',
    'GlacierMobileMemberRow',
    ['ready', 'invite', 'page-error'],
  ),
  (
    'access',
    'Member access',
    'GlacierMobileAccessEditor',
    ['ready', 'read-only', 'conflict'],
  ),
  (
    'invitations',
    'Invitations',
    'GlacierMobileInvitation',
    ['ready', 'expired'],
  ),
  (
    'signin',
    'Sign in',
    'GlacierMobileAuthForm',
    ['ready', 'register', 'restoring', 'expired', 'error'],
  ),
  (
    'server',
    'Server selection',
    'GlacierMobileServerEditor',
    ['ready', 'hosted', 'error', 'confirm'],
  ),
  (
    'account',
    'Account and password',
    'GlacierMobileSettingsForm',
    ['ready', 'password', 'saving', 'rejected', 'uncertain'],
  ),
  (
    'appearance',
    'Appearance',
    'GlacierMobileAppearance',
    ['ready', 'dark', 'opaque', 'reduced'],
  ),
  (
    'live-updates',
    'Live updates',
    'GlacierMobileNotice',
    ['ready', 'offline', 'stale'],
  ),
  (
    'email',
    'Email connections',
    'GlacierMobileRecordRow',
    ['ready', 'empty', 'error'],
  ),
  (
    'email-editor',
    'Email connection',
    'GlacierMobileSettingsForm',
    ['ready', 'credentials', 'rules', 'consent', 'checking', 'uncertain'],
  ),
  (
    'email-import',
    'Email import',
    'GlacierMobileImportOutcome',
    ['ready', 'running', 'failed'],
  ),
  (
    'paperless',
    'Paperless connection',
    'GlacierMobileSettingsForm',
    ['ready', 'checking', 'uncertain'],
  ),
  (
    'paperless-import',
    'Paperless import',
    'GlacierMobileImportOutcome',
    ['ready', 'running', 'partial', 'unknown'],
  ),
  (
    'paperless-outcomes',
    'Paperless outcomes',
    'GlacierMobileImportOutcome',
    ['ready', 'page-error'],
  ),
  (
    'ai',
    'Chat and AI',
    'GlacierMobileProviderFields',
    ['ready', 'external', 'disabled', 'uncertain'],
  ),
  (
    'processing-settings',
    'OCR and extraction',
    'GlacierMobileSettingsForm',
    ['ready', 'conflict', 'uncertain'],
  ),
  (
    'workload',
    'Workload limits',
    'GlacierMobileSettingsForm',
    ['ready', 'conflict', 'uncertain'],
  ),
  (
    'paperless-limits',
    'Paperless retrieval limits',
    'GlacierMobileSettingsForm',
    ['ready', 'conflict', 'uncertain'],
  ),
  ('users', 'System users', 'GlacierMobileMemberRow', ['ready', 'page-error']),
  (
    'user-access',
    'System user access',
    'GlacierMobileSettingsForm',
    ['ready', 'last-admin', 'conflict'],
  ),
  ('licenses', 'Licenses', 'GlacierMobileRecordRow', ['ready', 'detail']),
];

List<CatalogCase> mobileSettingsCases() => [
  for (final screen in _screens)
    for (final state in screen.$4)
      mobileScreenCase(
        screen: screen.$1,
        state: state,
        title: screen.$2,
        widgetType: screen.$3,
        domain: 'Mobile identity and settings',
        builder: (_) =>
            _SettingsExample(screen: screen.$1, initialState: state),
      ),
  for (final component in <(String, String, String)>[
    ('library-row', 'GlacierMobileLibraryRow', 'library'),
    ('member-row', 'GlacierMobileMemberRow', 'members'),
    ('access-selector', 'GlacierMobileAccessEditor', 'access'),
    ('auth-form', 'GlacierMobileAuthForm', 'signin'),
    ('server-form', 'GlacierMobileServerEditor', 'server'),
    ('settings-switch', 'GlacierMobilePermissionChoice', 'appearance'),
    ('appearance-choice', 'GlacierMobileAppearance', 'appearance'),
    ('connection-row', 'GlacierMobileRecordRow', 'email'),
    ('import-outcome', 'GlacierMobileImportOutcome', 'paperless-outcomes'),
  ])
    mobileComponentCase(
      id: component.$1,
      title: component.$1,
      widgetType: component.$2,
      referenceComponent: component.$1,
      builder: (_) =>
          _SettingsExample(screen: component.$3, initialState: 'ready'),
    ),
  for (final component in <(String, String, String, String)>[
    (
      'settings-section',
      'GlacierMobileSettingsSection',
      'settings-field',
      'workload',
    ),
    (
      'settings-form',
      'GlacierMobileSettingsForm',
      'settings-field',
      'workload',
    ),
    ('select-field', 'GlacierMobileSelectField', 'settings-field', 'access'),
    (
      'settings-disclosure',
      'GlacierMobileDisclosure',
      'settings-field',
      'email-editor',
    ),
    ('provider-fields', 'GlacierMobileProviderFields', 'settings-field', 'ai'),
    ('invitation', 'GlacierMobileInvitation', 'member-row', 'invitations'),
  ])
    mobileComponentCase(
      id: component.$1,
      title: component.$1,
      widgetType: component.$2,
      referenceComponent: component.$3,
      builder: (_) =>
          _SettingsExample(screen: component.$4, initialState: 'ready'),
    ),
  mobileComponentCase(
    id: 'field-group',
    title: 'Paired form fields',
    widgetType: 'GlacierMobileFieldGroup',
    referenceComponent: 'settings-field',
    builder: (_) => const Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: GlacierMobileFieldGroup(
          children: [
            GlacierMobileField(
              label: 'Email',
              initialValue: 'alex@example.com',
            ),
            GlacierMobileField(label: 'Password', obscureText: true),
          ],
        ),
      ),
    ),
  ),
];

class _SettingsExample extends StatefulWidget {
  const _SettingsExample({required this.screen, required this.initialState});
  final String screen, initialState;
  @override
  State<_SettingsExample> createState() => _SettingsExampleState();
}

class _SettingsExampleState extends State<_SettingsExample> {
  late String state = widget.initialState;
  final controllers = <String, TextEditingController>{};
  final choices = <String, bool>{};
  final selections = <String, String>{};
  final workload = SampleWorkload(ingestions: 1, workerLimit: 4);
  bool recovered = false;
  late String mode = state == 'dark' ? 'dark' : 'system';
  String background = 'activity';
  late bool opaque = state == 'opaque', reduced = state == 'reduced';
  bool get pending =>
      !recovered &&
      ['uncertain', 'conflict', 'saving', 'checking'].contains(state);
  TextEditingController controller(String label, [String value = '']) =>
      controllers.putIfAbsent(label, () => TextEditingController(text: value));
  @override
  void dispose() {
    for (final value in controllers.values) {
      value.dispose();
    }
    super.dispose();
  }

  void go(String screen, [String next = 'ready', Object? arguments]) =>
      mobileCatalogNavigate(context, screen, state: next, arguments: arguments);
  void preview([
    String message = 'Changes applied to this fictional example.',
  ]) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  Widget text(String value) => Builder(
    builder: (context) =>
        Text(value, style: TextStyle(color: GlacierTokens.of(context).muted)),
  );
  Widget stack(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++)
        Padding(
          padding: EdgeInsets.only(
            top:
                i == 0 ||
                    children[i] is GlacierMobileSettingsSection ||
                    children[i] is GlacierMobileRecordRow ||
                    children[i] is GlacierMobileLibraryRow ||
                    children[i] is GlacierMobileMemberRow
                ? 0
                : 8,
          ),
          child: children[i],
        ),
    ],
  );
  Widget section(String title, Widget child, {String? description}) =>
      GlacierMobileSettingsSection(
        title: title,
        description: description,
        first:
            title ==
            switch (widget.screen) {
              'more' => 'Your workspace',
              'library' => 'Choose a library',
              'libraries' => 'Your libraries',
              'members' => 'Library members',
              'account' => 'Your account',
              'live-updates' => 'Live updates',
              'email' => 'Email accounts',
              'email-editor' => 'Email connection',
              'email-import' => 'Email import',
              'paperless' => 'Import from Paperless-ngx',
              'paperless-import' => 'Paperless import',
              'paperless-outcomes' => 'Import outcomes',
              'ai' => 'AI chat',
              'processing-settings' => 'Document processing',
              'workload' => 'Pipelines',
              'paperless-limits' => 'Paperless retrievals',
              'users' => 'System users',
              'user-access' => 'System role',
              'licenses' =>
                state == 'detail' ? 'DM Sans' : 'Open-source licenses',
              _ => '',
            },
        child: child,
      );
  Widget button(String label, VoidCallback? action, {bool danger = false}) =>
      GlacierButton(
        label: label,
        onPressed: action,
        kind: danger ? GlacierButtonKind.danger : GlacierButtonKind.secondary,
      );
  Widget link(
    String label,
    String target, [
    String next = 'ready',
    bool danger = false,
  ]) => button(label, () => go(target, next), danger: danger);
  Widget actions(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: GlacierMobileActionBar(children: children),
  );
  Widget field(
    String label, [
    String value = '',
    TextInputType? type,
    bool secret = false,
  ]) => GlacierMobileField(
    label: label,
    controller: controller(label, value),
    keyboardType: type,
    obscureText: secret,
    enabled: !pending,
  );
  Widget select(String label, List<String> options) => GlacierMobileSelectField(
    label: label,
    value: selections[label] ?? options.first,
    options: options,
    onChanged: pending
        ? null
        : (value) => setState(() => selections[label] = value),
  );
  Widget choice(
    String label, [
    bool selected = false,
    String? detail,
    bool inherited = false,
  ]) => GlacierMobilePermissionChoice(
    label: label,
    selected: choices[label] ?? selected,
    detail: detail,
    onChanged: pending || inherited
        ? null
        : (value) => setState(() => choices[label] = value),
  );
  Widget row(
    String title,
    String detail,
    String? target, {
    IconData icon = Icons.chevron_right,
    String next = 'ready',
  }) => GlacierMobileRecordRow(
    title: title,
    detail: detail,
    icon: icon,
    onTap: target == null ? null : () => go(target, next),
  );
  Widget notice(
    String title,
    String message, {
    Widget? action,
    bool attention = true,
  }) => GlacierMobileNotice(
    title: title,
    message: message,
    action: action,
    attention: attention,
  );
  Widget? recovery() => !pending
      ? null
      : notice(
          state == 'conflict'
              ? 'The saved value changed'
              : state == 'uncertain'
              ? 'The result is not confirmed'
              : state == 'saving'
              ? 'Saving…'
              : 'Checking…',
          state == 'conflict'
              ? 'Review the latest value before applying your retained draft.'
              : state == 'uncertain'
              ? 'Your draft is retained. Check the saved value before making another change.'
              : 'Keep this screen open while the request is pending.',
          action: ['conflict', 'uncertain'].contains(state)
              ? button(
                  state == 'conflict'
                      ? 'Reload saved value'
                      : 'Check saved value',
                  () => setState(() => recovered = true),
                )
              : null,
        );
  Widget form(List<Widget> children, String label, {VoidCallback? onSubmit}) =>
      GlacierMobileSettingsForm(
        submitLabel: label,
        onSubmit: pending ? null : onSubmit ?? () => preview(),
        feedback: recovery(),
        enabled: !pending,
        busy: state == 'saving' || state == 'checking',
        children: children,
      );
  Widget continuation(String noun) => state == 'page-error'
      ? notice(
          'Could not load more $noun',
          'Items already loaded are still available.',
          action: button(
            'Retry loading',
            () => setState(() => state = 'ready'),
          ),
        )
      : button(
          'Load more $noun',
          () => preview('The next bounded page is requested in this example.'),
        );
  Widget provider({bool extraction = false, bool external = false}) =>
      GlacierMobileProviderFields(
        provider:
            selections['provider'] ??
            (external ? 'External service' : 'Internal Ollama'),
        model: controller('Model', external ? 'local-model' : 'qwen3:8b').text,
        baseUrl: controller('API base URL', 'https://ai.example.com/v1').text,
        onProviderChanged: (value) =>
            setState(() => selections['provider'] = value),
        onModelChanged: (value) => controller('Model').text = value,
        onBaseUrlChanged: (value) => controller('API base URL').text = value,
        onKeyChanged: (value) => controller('Replacement API key').text = value,
        removeKey: choices['removeKey'] ?? false,
        onRemoveKeyChanged: (value) =>
            setState(() => choices['removeKey'] = value),
        extraction: extraction,
        compatibility: choices['compatibility'] ?? false,
        onCompatibilityChanged: (value) =>
            setState(() => choices['compatibility'] = value),
      );

  Widget content() {
    switch (widget.screen) {
      case 'more':
        final restricted = state == 'restricted';
        return stack([
          section(
            'Your workspace',
            stack([
              row(
                'Personal library',
                'Current destination for uploads',
                'library',
                icon: Icons.library_books_outlined,
              ),
              row(
                'Account',
                'alex@example.com',
                'account',
                icon: Icons.person_outline,
              ),
              row(
                'Appearance',
                'System · Activity background',
                'appearance',
                icon: Icons.light_mode_outlined,
              ),
              row(
                'Live updates',
                'Connected',
                'live-updates',
                icon: Icons.monitor_heart_outlined,
              ),
              row(
                'Your jobs',
                '2 jobs in progress',
                'jobs',
                icon: Icons.monitor_heart_outlined,
              ),
            ]),
          ),
          section(
            'Settings',
            stack([
              row(
                'Libraries',
                'Manage access and invitations',
                'libraries',
                icon: Icons.library_books_outlined,
              ),
              if (!restricted) ...[
                row(
                  'Members',
                  'People in this library',
                  'members',
                  icon: Icons.people_outline,
                ),
                row(
                  'Invitations',
                  'Invite someone to your library',
                  'invitations',
                  icon: Icons.mail_outline,
                ),
                row(
                  'Email accounts',
                  'Import mail and attachments',
                  'email',
                  icon: Icons.mail_outline,
                ),
                row(
                  'Paperless import',
                  'Bring existing documents into this library',
                  'paperless',
                  icon: Icons.download_outlined,
                ),
              ],
              row(
                'Server',
                'Native app connection',
                'server',
                icon: Icons.dns_outlined,
              ),
              row(
                'Licenses',
                'Open-source notices',
                'licenses',
                icon: Icons.description_outlined,
              ),
            ]),
          ),
          if (!restricted)
            section(
              'Administration',
              stack([
                row(
                  'System users',
                  'Installation roles, separate from library access',
                  'users',
                  icon: Icons.people_outline,
                ),
                row(
                  'Workload limits',
                  'Shared worker capacity',
                  'workload',
                  icon: Icons.tune,
                ),
                row(
                  'AI chat',
                  'Provider and credentials',
                  'ai',
                  icon: Icons.chat_bubble_outline,
                ),
                row(
                  'Document processing',
                  'OCR and extraction',
                  'processing-settings',
                  icon: Icons.settings_outlined,
                ),
                row(
                  'Paperless retrievals',
                  'Import concurrency',
                  'paperless-limits',
                  icon: Icons.download_outlined,
                ),
              ]),
            )
          else
            notice(
              'Limited library access',
              'Only destinations allowed by your permissions are shown.',
            ),
          actions([link('Sign out', 'confirm', 'signout', true)]),
        ]);
      case 'library':
        if (state == 'empty') {
          return notice(
            'No library access yet',
            'Create a library or accept an invitation to begin.',
            action: link('Manage libraries', 'libraries'),
          );
        }
        if (state == 'error') {
          return notice(
            'Libraries could not load',
            'Your current library has not changed.',
            action: button('Try again', () => setState(() => state = 'ready')),
          );
        }
        return stack([
          section(
            'Choose a library',
            stack([
              GlacierMobileLibraryRow(
                name: 'Personal library',
                detail: mobileCatalogLibrary(context) == 'Personal'
                    ? 'Current · Owner'
                    : 'Owner',
                selected: mobileCatalogLibrary(context) == 'Personal',
                onSelect: () =>
                    MobileCatalogScope.maybeOf(context)?.session
                        .selectLibrary('Personal'),
              ),
              GlacierMobileLibraryRow(
                name: 'Family archive',
                detail: mobileCatalogLibrary(context) == 'Family archive'
                    ? 'Current · Member'
                    : 'Member · 248 documents',
                selected: mobileCatalogLibrary(context) == 'Family archive',
                onSelect: () =>
                    MobileCatalogScope.maybeOf(context)?.session
                        .selectLibrary('Family archive'),
              ),
            ]),
          ),
          actions([link('Manage libraries', 'libraries')]),
        ]);
      case 'libraries':
        return stack([
          section(
            'Your libraries',
            stack([
              GlacierMobileLibraryRow(
                name: 'Personal library',
                detail: 'Owner',
                selected: mobileCatalogLibrary(context) == 'Personal',
                onSelect: () => go('library'),
              ),
              GlacierMobileLibraryRow(
                name: 'Family archive',
                detail: 'Member',
                onSelect: () => go('library'),
              ),
              continuation('libraries'),
            ]),
          ),
          section(
            'Accept an invitation',
            stack([
              field('Invitation code'),
              actions([button('Accept invitation', () => preview())]),
            ]),
          ),
          section(
            'Create a library',
            stack([
              field(
                'Library name',
                state == 'create' ? 'Household archive' : '',
              ),
              actions([button('Create library', () => preview())]),
            ]),
          ),
        ]);
      case 'members':
        return stack([
          section(
            'Library members',
            stack([
              GlacierMobileMemberRow(
                name: 'Alex Morgan',
                detail: 'Owner · Active',
                onOpen: () => go('access', 'read-only'),
              ),
              GlacierMobileMemberRow(
                name: 'Jamie Morgan',
                detail: 'Member · Active',
                onOpen: () => go('access'),
              ),
              continuation('members'),
            ]),
          ),
          section(
            'Invite a member',
            stack([
              GlacierMobileFieldGroup(
                children: [
                  field('Recipient email', '', TextInputType.emailAddress),
                  select('Library role', ['User', 'Viewer', 'Admin']),
                ],
              ),
              GlacierMobileDisclosure(
                label: 'Choose explicit permissions',
                child: stack([
                  choice('Read documents', true),
                  choice('Upload documents', true),
                  choice('Manage library members'),
                ]),
              ),
              actions([link('Create invitation', 'invitations')]),
            ]),
          ),
        ]);
      case 'access':
        return stack([
          GlacierMobileAccessEditor(
            name: 'Jamie Morgan',
            role: selections['role'] ?? 'User',
            enabled: choices['enabled'] ?? true,
            readOnly: state == 'read-only',
            permissions: [
              const GlacierMobilePermissionValue(
                id: 'read',
                label: 'Read documents',
                selected: true,
                inherited: true,
              ),
              const GlacierMobilePermissionValue(
                id: 'upload',
                label: 'Upload documents',
                selected: true,
                inherited: true,
              ),
              for (final permission in [
                ('metadata', 'Create metadata'),
                ('members', 'Manage members'),
                ('email', 'Manage email accounts'),
              ])
                GlacierMobilePermissionValue(
                  id: permission.$1,
                  label: permission.$2,
                  selected: choices[permission.$1] ?? false,
                ),
            ],
            onRoleChanged: (value) =>
                setState(() => selections['role'] = value),
            onEnabledChanged: (value) =>
                setState(() => choices['enabled'] = value),
            onPermissionChanged: (id, value) =>
                setState(() => choices[id] = value),
            onSave: pending ? null : () => preview(),
            feedback: recovery(),
          ),
          if (state == 'read-only')
            notice(
              'Owner access',
              'Owners inherit registered library permissions. Ownership is not an editable permission toggle.',
            ),
        ]);
      case 'invitations':
        return stack([
          GlacierMobileInvitation(
            email: 'jamie@example.com',
            status: state == 'expired'
                ? 'Expired · User'
                : 'Pending · User · Expires 24 November',
            code: state == 'expired' ? null : 'HOME-8Q2J-4M7C',
            onCopy: () async {
              await Clipboard.setData(
                const ClipboardData(text: 'HOME-8Q2J-4M7C'),
              );
              if (mounted) preview('Invitation code copied.');
            },
            onRevoke: () => go('confirm', 'revoke'),
            onInviteAgain: state == 'expired'
                ? () => go('members', 'invite')
                : null,
          ),
          actions([link('Invite member', 'members', 'invite')]),
        ]);
      case 'signin':
        if (state == 'restoring') {
          return notice(
            'Restoring your session…',
            'Your library will open when the session is checked.',
          );
        }
        return stack([
          GlacierMobileAuthForm(
            email: controller('Email', 'alex@example.com'),
            password: controller('Password'),
            name: controller('Account name'),
            register: state == 'register',
            feedback: state == 'expired'
                ? notice(
                    'Sign in again',
                    'Your session expired. Your incoming shared files are waiting on this device.',
                  )
                : state == 'error'
                ? notice(
                    'Could not sign in',
                    'Check your email and password, then try again.',
                  )
                : null,
            onSubmit: () =>
                preview('Fictional sign-in complete. No session was created.'),
            onChangeMode: () => setState(
              () => state = state == 'register' ? 'ready' : 'register',
            ),
          ),
          actions([link('Change server', 'server')]),
        ]);
      case 'server':
        return stack([
          GlacierMobileServerEditor(
            controller: controller(
              'Server address',
              'https://documents.example.com',
            ),
            hosted: state == 'hosted',
            feedback: state == 'error'
                ? notice(
                    'Server is not reachable',
                    'Check the address and network connection. Your saved server has not changed.',
                  )
                : null,
            onCheck: () => setState(() => state = 'confirm'),
          ),
          if (state == 'confirm')
            notice(
              'Change server?',
              'You will sign out of this server. Finish any shared-file import before changing servers.',
              action: actions([
                button('Change server', () => preview()),
                button(
                  'Keep current server',
                  () => setState(() => state = 'ready'),
                ),
              ]),
            ),
        ]);
      case 'account':
        return stack([
          section(
            'Your account',
            stack([
              const GlacierMobileMemberRow(
                name: 'Alex Morgan',
                detail: 'alex@example.com',
                onOpen: null,
              ),
              row(
                'Password',
                'Change your account password',
                'account',
                icon: Icons.lock_outline,
                next: 'password',
              ),
            ]),
          ),
          section(
            'Change password',
            stack([
              if (state == 'rejected')
                notice(
                  'Password was not changed',
                  'The current password was not accepted. Check it and try again.',
                ),
              form([
                GlacierMobileFieldGroup(
                  children: [
                    field('Current password', '', null, true),
                    field('New password', '', null, true),
                    field('Confirm new password', '', null, true),
                  ],
                ),
              ], 'Change password'),
            ]),
          ),
          actions([link('Sign out', 'confirm', 'signout', true)]),
        ]);
      case 'appearance':
        return GlacierMobileAppearance(
          mode: mode,
          background: background,
          reduceTransparency: opaque,
          reduceMotion: reduced,
          onModeChanged: (value) => setState(() => mode = value),
          onBackgroundChanged: (value) => setState(() => background = value),
          onTransparencyChanged: (value) => setState(() => opaque = value),
          onMotionChanged: (value) => setState(() => reduced = value),
        );
      case 'live-updates':
        return section(
          'Live updates',
          stack([
            notice(
              state == 'offline'
                  ? 'Connection interrupted'
                  : state == 'stale'
                  ? 'Updates are delayed'
                  : 'Connected',
              state == 'ready'
                  ? 'Changes in this library appear automatically.'
                  : 'The information already loaded is still available. Reconnect or refresh to check for changes.',
              attention: state != 'ready',
              action: state == 'ready'
                  ? null
                  : button('Reconnect', () => setState(() => state = 'ready')),
            ),
            text(
              'Live updates do not change whether a background job continues running.',
            ),
          ]),
        );
      case 'email':
        return stack([
          if (state == 'error')
            notice(
              'Email accounts could not load',
              'Try again without changing saved connections.',
              action: button(
                'Try again',
                () => setState(() => state = 'ready'),
              ),
            )
          else if (state == 'empty')
            notice(
              'No email accounts connected',
              'Import email and supported attachments into this library.',
              attention: false,
              action: link('Add email account', 'email-editor'),
            )
          else
            section(
              'Email accounts',
              stack([
                row(
                  'Household inbox',
                  'Automatic import · Last checked 4 minutes ago',
                  'email-editor',
                  icon: Icons.mail_outline,
                ),
                row(
                  'Import history',
                  'Recent email jobs and outcomes',
                  'email-import',
                  icon: Icons.monitor_heart_outlined,
                ),
              ]),
            ),
          actions([link('Add email account', 'email-editor')]),
        ]);
      case 'email-editor':
        return stack([
          section(
            'Email connection',
            form([
              text(
                'Destination: Personal library. Supported attachments are imported with their email.',
              ),
              section(
                'Connection',
                stack([
                  GlacierMobileFieldGroup(
                    children: [
                      field('Account label', 'Household inbox'),
                      field('IMAP host or imaps:// URL', 'imap.example.com'),
                      field('Port', '993', TextInputType.number),
                      field('Username', 'home@example.com'),
                      field('Password or app password', '', null, true),
                    ],
                  ),
                  text(
                    'Leave the password empty to keep the saved credential. IMAP uses implicit TLS.',
                  ),
                  actions([
                    button(
                      'Test connection',
                      pending ? null : () => setState(() => state = 'checking'),
                    ),
                  ]),
                ]),
              ),
              GlacierMobileDisclosure(
                label: 'Import rules',
                initiallyExpanded: state == 'rules',
                child: section(
                  'Import rules',
                  stack([
                    GlacierMobileFieldGroup(
                      children: [
                        field('Mailbox', 'INBOX'),
                        field(
                          'Check every (minutes)',
                          '15',
                          TextInputType.number,
                        ),
                        field(
                          'Maximum email age (days)',
                          '365',
                          TextInputType.number,
                        ),
                        field('Messages per page', '50', TextInputType.number),
                      ],
                    ),
                    text(
                      'Increasing the maximum age also looks for older mail.',
                    ),
                  ]),
                ),
              ),
              choice(
                'Enable automatic import',
                true,
                'Continues after sign-out. Disable or delete this account to stop future imports.',
              ),
            ], 'Save email account'),
          ),
          if (state == 'credentials')
            notice(
              'Saved credentials need checking',
              'A previous credential update was not confirmed. Test the saved credentials before replacing them again.',
              action: button(
                'Test saved credentials',
                () => setState(() => state = 'checking'),
              ),
            ),
          actions([
            link('Import history', 'email-import'),
            link('Delete email account', 'confirm', 'delete-email', true),
          ]),
        ]);
      case 'email-import':
        return stack([
          section(
            'Email import',
            stack([
              GlacierMobileImportOutcome(
                title: 'Household inbox',
                outcome: state == 'failed'
                    ? 'Failed'
                    : state == 'running'
                    ? 'Running'
                    : 'Completed',
                detail: state == 'failed'
                    ? 'Authentication rejected'
                    : state == 'running'
                    ? 'Reading mailbox'
                    : '18 messages checked',
                attention: state == 'failed',
                onOpen: () => go('job-detail', 'email'),
              ),
              if (state == 'failed')
                notice(
                  'The mailbox rejected the login',
                  'Review the saved username and app password before retrying.',
                  action: link(
                    'Review connection',
                    'email-editor',
                    'credentials',
                  ),
                )
              else
                text(
                  'Accepted email and attachments remain in Personal library.',
                ),
            ]),
          ),
          actions([
            link('Open job details', 'job-detail', 'email'),
            button(
              'Load older imports',
              () => preview(
                'The next bounded page is requested in this example.',
              ),
            ),
          ]),
        ]);
      case 'paperless':
        return stack([
          section(
            'Import from Paperless-ngx',
            form(
              [
                text(
                  'Bring documents into Personal library. This is a background import, not a two-way sync.',
                ),
                GlacierMobileFieldGroup(
                  children: [
                    field(
                      'Paperless server URL',
                      'https://paperless.example.com',
                      TextInputType.url,
                    ),
                    field('Paperless API token', '', null, true),
                  ],
                ),
                text(
                  'Use an address your Domabas server can reach. Find the token in Paperless → My Profile.',
                ),
                notice(
                  'Destination: Personal library',
                  'The import continues after leaving this screen or signing out. The token is encrypted while the job runs and erased when it finishes. Cancelling keeps documents already accepted.',
                  attention: false,
                ),
              ],
              'Start import',
              onSubmit: () => go('paperless-import', 'running'),
            ),
          ),
          actions([link('Import history', 'paperless-import')]),
        ]);
      case 'paperless-import':
        return stack([
          section(
            'Paperless import',
            stack([
              GlacierMobileImportOutcome(
                title: 'Personal library import',
                outcome: state == 'partial'
                    ? 'Partially completed'
                    : ['running', 'unknown'].contains(state)
                    ? 'Running'
                    : 'Completed',
                detail: state == 'partial'
                    ? 'Some files need attention'
                    : state == 'unknown'
                    ? 'Discovering documents'
                    : state == 'running'
                    ? 'Retrieving originals'
                    : '48 documents accepted',
                attention: state == 'partial',
                onOpen: () => go('paperless-outcomes'),
              ),
              if (state == 'unknown')
                notice(
                  'Total is not known yet',
                  'Paperless is still listing documents. Progress appears when the source reports a total.',
                )
              else if (state == 'partial')
                notice(
                  'Some files were not imported',
                  'Review individual outcomes. Accepted documents are already in your library.',
                  action: link('Review outcomes', 'paperless-outcomes'),
                )
              else
                text('Documents continue processing after they are accepted.'),
            ]),
          ),
          actions([
            link('View outcomes', 'paperless-outcomes'),
            link('Processing details', 'job-detail', 'paperless'),
            if (['running', 'unknown'].contains(state))
              link('Cancel import', 'confirm', 'cancel-import', true),
          ]),
          continuation('imports'),
        ]);
      case 'paperless-outcomes':
        return section(
          'Import outcomes',
          stack([
            GlacierMobileImportOutcome(
              title: 'Home insurance.pdf',
              outcome: 'Accepted',
              detail: 'Processing in Domabas',
              onOpen: () => go('reader', 'ready', 'insurance'),
            ),
            GlacierMobileImportOutcome(
              title: 'Energy bill.pdf',
              outcome: 'Duplicate',
              detail: 'Already in this library',
              onOpen: () => go('reader', 'ready', 'energy'),
            ),
            GlacierMobileImportOutcome(
              title: 'Archive scan.pdf',
              outcome: 'Rejected',
              detail: 'Source file unavailable',
              attention: true,
              onOpen: () => go('job-detail', 'paperless'),
            ),
            GlacierMobileImportOutcome(
              title: 'Tax records.pdf',
              outcome: 'Not confirmed',
              detail: 'Check before retrying',
              attention: true,
              onOpen: () => go('job-detail', 'unknown'),
            ),
            continuation('outcomes'),
          ]),
        );
      case 'paperless-limits':
        return stack([
          section(
            'Paperless retrievals',
            form([
              text('Controls concurrent retrievals across this installation.'),
              field('Parallel retrievals', '2', TextInputType.number),
            ], 'Save retrieval settings'),
          ),
          section(
            'Shared worker capacity',
            stack([
              text(
                'Imports also share worker limits with other background jobs. Each import retrieves files one at a time; requests back off when Paperless is unavailable.',
              ),
              actions([link('Workload limits', 'workload')]),
            ]),
          ),
        ]);
      case 'ai':
        return stack([
          section(
            'AI chat',
            form([
              choice(
                'Enable AI chat',
                state != 'disabled',
                'Allow people with chat access to ask questions about library documents.',
              ),
              choice(
                'Enable thinking for chat',
                false,
                'The model may take longer to reason before replying.',
              ),
              provider(external: state == 'external'),
            ], 'Save chat settings'),
          ),
          section(
            'Shared resources',
            stack([
              text('Chat inference shares resources with document extraction.'),
              actions([link('Workload limits', 'workload')]),
            ]),
          ),
        ]);
      case 'processing-settings':
        return stack([
          section(
            'Document processing',
            form([
              section(
                'Pipelines',
                stack([
                  row(
                    'Document ingestion',
                    'Original → OCR → embeddings → searchable publication',
                    'job-detail',
                    icon: Icons.description_outlined,
                    next: 'ingestion',
                  ),
                  row(
                    'AI processing',
                    'After ingestion · Optional failures leave documents searchable',
                    'job-detail',
                    icon: Icons.monitor_heart_outlined,
                    next: 'ai',
                  ),
                  row(
                    'Thumbnail generation',
                    'Automatic previews · Worker capacity only',
                    'job-detail',
                    icon: Icons.image_outlined,
                    next: 'thumbnail',
                  ),
                ]),
              ),
              section(
                'OCR',
                stack([
                  notice(
                    'Applies to every library',
                    'Saving an OCR change automatically reprocesses existing originals across every library. Saved text corrections are retained.',
                  ),
                  GlacierMobileFieldGroup(
                    children: [
                      select('OCR language', [
                        'English',
                        'German',
                        'English + German',
                      ]),
                      select('Page layout', [
                        'Automatic',
                        'Single column',
                        'Sparse text',
                      ]),
                    ],
                  ),
                ]),
              ),
              GlacierMobileDisclosure(
                label: 'Invoice and property extraction',
                initiallyExpanded: true,
                child: stack([
                  choice('Enable AI invoice extraction', true),
                  choice('Enable thinking for invoices'),
                  choice('Enable AI property extraction', true),
                  choice('Enable thinking for properties'),
                  provider(extraction: true, external: true),
                ]),
              ),
            ], 'Save processing settings'),
          ),
          section(
            'Reindex originals',
            stack([
              text(
                'Reprocess existing originals independently from changing these settings.',
              ),
              actions([
                link('Reindex this library', 'reindex'),
                link('Installation reindex requests', 'reindex', 'system'),
              ]),
            ]),
          ),
        ]);
      case 'workload':
        TextEditingController limitField(String id) =>
            controller('workload-$id', '${workload.limits[id]}');
        final valid = workload.limits.keys.every(
          (id) => workload.validate(id, limitField(id).text) == null,
        );
        return stack([
          ?recovery(),
          WorkloadFlowPreview(
            sample: workload,
            onLoad: (value) => setState(() => workload.ingestions = value),
          ),
          GlacierMobileSettingsForm(
            enabled: !pending,
            submitLabel: 'Save limits',
            onSubmit: pending || !valid
                ? null
                : () {
                    setState(
                      () => workload.limits.updateAll(
                        (id, _) => int.parse(limitField(id).text),
                      ),
                    );
                    preview('Sample limits saved.');
                  },
            children: [
              for (final pipelines in [true, false])
                section(
                  pipelines ? 'Pipelines' : 'Shared resources',
                  GlacierMobileFieldGroup(
                    children: [
                      for (final id in workload.limits.keys.where(
                        (id) => id.startsWith('pipeline:') == pipelines,
                      ))
                        GlacierMobileField(
                          label: '${workload.label(id)} maximum parallel',
                          controller: limitField(id),
                          keyboardType: TextInputType.number,
                          enabled: !pending,
                          errorText: workload.validate(id, limitField(id).text),
                          onChanged: (_) => setState(() {}),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: button(
              'Use saved limits',
              pending
                  ? null
                  : () => setState(() {
                      for (final entry in workload.limits.entries) {
                        limitField(entry.key).text = '${entry.value}';
                      }
                    }),
            ),
          ),
        ]);
      case 'users':
        return section(
          'System users',
          stack([
            text(
              'System administration is separate from membership and permissions in any library.',
            ),
            GlacierMobileMemberRow(
              name: 'Alex Morgan',
              detail: 'Your account · Last system administrator',
              onOpen: () => go('user-access', 'last-admin'),
            ),
            GlacierMobileMemberRow(
              name: 'Jamie Morgan',
              detail: 'User',
              onOpen: () => go('user-access'),
            ),
            continuation('users'),
          ]),
        );
      case 'user-access':
        return stack([
          section(
            'System role',
            stack([
              const GlacierMobileMemberRow(
                name: 'Alex Morgan',
                detail: 'alex@example.com',
                onOpen: null,
              ),
              ?recovery(),
              notice(
                'Last administrator',
                'Promote another user before removing this role. Library access is managed separately.',
              ),
              const GlacierMobileSelectField(
                label: 'System role',
                value: 'System administrator',
                options: ['System administrator', 'User'],
                onChanged: null,
              ),
              button('Remove administrator', null),
              GlacierMobileDisclosure(
                label: 'Another user',
                child: stack([
                  const GlacierMobileMemberRow(
                    name: 'Jamie Morgan',
                    detail: 'jamie@example.com · User',
                    onOpen: null,
                  ),
                  actions([
                    button(
                      'Promote administrator',
                      pending ? null : () => preview(),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
          actions([link('Library members', 'members')]),
        ]);
      case 'licenses':
        return state == 'detail'
            ? section(
                'DM Sans',
                stack([
                  text(
                    'Copyright 2014–2020 The DM Sans Project Authors. Licensed under the SIL Open Font License, Version 1.1.',
                  ),
                  const GlacierMobileSurface(
                    child: Text(
                      'This preview demonstrates the readable license-detail layout. The application displays the complete bundled license text for the selected package.\n\nThe font may be used, studied, modified and redistributed under the terms of its license. Copyright and license notices remain with redistributed copies.',
                    ),
                  ),
                  actions([
                    button(
                      'All licenses',
                      () => setState(() => state = 'ready'),
                    ),
                  ]),
                ]),
              )
            : section(
                'Open-source licenses',
                stack([
                  GlacierMobileField(
                    label: 'Find a package',
                    controller: controller('Find a package'),
                    onChanged: (_) => setState(() {}),
                  ),
                  for (final package in [
                    ('DM Sans', 'SIL Open Font License 1.1'),
                    ('Flutter', 'BSD-style license'),
                    ('PDF viewer', 'Package license notices'),
                  ])
                    if (package.$1.toLowerCase().contains(
                      controller('Find a package').text.toLowerCase(),
                    ))
                      row(
                        package.$1,
                        package.$2,
                        'licenses',
                        icon: Icons.description_outlined,
                        next: 'detail',
                      ),
                ]),
              );
      default:
        throw StateError(
          'Unregistered mobile settings screen ${widget.screen}',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.screen == 'more'
        ? 'More'
        : _screens.firstWhere((value) => value.$1 == widget.screen).$2;
    final scoped = widget.screen == 'appearance';
    final inherited = Theme.of(context);
    final dark =
        mode == 'dark' ||
        mode == 'system' && inherited.brightness == Brightness.dark;
    return Theme(
      data: scoped
          ? glacierMobileTheme(
              dark
                  ? GlacierTheme.dark(opaque: opaque)
                  : GlacierTheme.light(opaque: opaque),
              platform: inherited.platform,
            )
          : inherited,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: scoped
              ? reduced
              : MediaQuery.disableAnimationsOf(context),
        ),
        child: Builder(
          builder: (context) => mobileCatalogShell(
            context,
            title: title,
            subtitle: widget.screen == 'workload' ? 'All libraries' : 'Personal library',
            selectedId: 'more',
            showNavigation: widget.screen != 'signin',
            showLibrary: widget.screen == 'more',
            activityBackground: !scoped || background == 'activity',
            onBack: widget.screen == 'more'
                ? null
                : () => Navigator.maybePop(context),
            child: SizedBox(width: double.infinity, child: content()),
          ),
        ),
      ),
    );
  }
}
