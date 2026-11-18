import 'package:flutter/material.dart';

import 'glacier_controls.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_mobile_settings.dart';

class GlacierMobileLibraryRow extends StatelessWidget {
  const GlacierMobileLibraryRow({
    super.key,
    required this.name,
    required this.detail,
    required this.onSelect,
    this.selected = false,
  });
  final String name, detail;
  final bool selected;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => GlacierMobileRecordRow(
    title: name,
    detail: detail,
    icon: selected ? Icons.check : Icons.library_books_outlined,
    onTap: onSelect,
  );
}

class GlacierMobileMemberRow extends StatelessWidget {
  const GlacierMobileMemberRow({
    super.key,
    required this.name,
    required this.detail,
    required this.onOpen,
  });
  final String name, detail;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => GlacierMobileRecordRow(
    title: name,
    detail: detail,
    icon: Icons.person_outline,
    onTap: onOpen,
  );
}

class GlacierMobileAuthForm extends StatelessWidget {
  const GlacierMobileAuthForm({
    super.key,
    required this.email,
    required this.password,
    required this.onSubmit,
    required this.onChangeMode,
    this.name,
    this.register = false,
    this.feedback,
    this.busy = false,
  });
  final TextEditingController email, password;
  final TextEditingController? name;
  final VoidCallback? onSubmit;
  final VoidCallback onChangeMode;
  final bool register, busy;
  final Widget? feedback;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?feedback,
      GlacierMobileSettingsSection(
        title: register ? 'Create your account' : 'Welcome back',
        first: feedback == null,
        description: 'Your private documents, in one place.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (register)
              GlacierMobileField(label: 'Account name', controller: name),
            GlacierMobileFieldGroup(
              children: [
                GlacierMobileField(
                  label: 'Email',
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                ),
                GlacierMobileField(
                  label: 'Password',
                  controller: password,
                  obscureText: true,
                ),
              ],
            ),
            GlacierMobileActionBar(
              children: [
                GlacierButton(
                  label: register ? 'Create account' : 'Sign in',
                  onPressed: onSubmit,
                  busy: busy,
                ),
                GlacierButton(
                  label: register
                      ? 'Already have an account?'
                      : 'Create an account',
                  onPressed: onChangeMode,
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class GlacierMobileServerEditor extends StatelessWidget {
  const GlacierMobileServerEditor({
    super.key,
    required this.controller,
    required this.onCheck,
    this.feedback,
    this.hosted = false,
  });
  final TextEditingController controller;
  final VoidCallback? onCheck;
  final Widget? feedback;
  final bool hosted;
  @override
  Widget build(BuildContext context) => GlacierMobileSettingsSection(
    title: hosted ? 'Server' : 'Connect to Domabas',
    first: true,
    description: hosted
        ? null
        : 'Use the address of your household or self-hosted server.',
    child: hosted
        ? const GlacierMobileNotice(
            title: 'Connected to this website',
            message: 'The hosted app uses its current origin. Server selection is available in the native apps.',
            attention: false,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?feedback,
              GlacierMobileField(
                label: 'Server address',
                controller: controller,
                keyboardType: TextInputType.url,
              ),
              GlacierButton(label: 'Check server', onPressed: onCheck),
            ],
          ),
  );
}

@immutable
class GlacierMobilePermissionValue {
  const GlacierMobilePermissionValue({
    required this.id,
    required this.label,
    required this.selected,
    this.detail,
    this.inherited = false,
  });
  final String id, label;
  final String? detail;
  final bool selected, inherited;
}

class GlacierMobileAccessEditor extends StatelessWidget {
  const GlacierMobileAccessEditor({
    super.key,
    required this.name,
    required this.role,
    required this.enabled,
    required this.permissions,
    required this.onRoleChanged,
    required this.onEnabledChanged,
    required this.onPermissionChanged,
    required this.onSave,
    this.feedback,
    this.readOnly = false,
  });
  final String name, role;
  final bool enabled, readOnly;
  final List<GlacierMobilePermissionValue> permissions;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(String, bool) onPermissionChanged;
  final VoidCallback? onSave;
  final Widget? feedback;
  @override
  Widget build(BuildContext context) => GlacierMobileSettingsSection(
    title: name,
    first: true,
    description: 'Library roles and explicit permissions apply only to Personal library. System administrator access is managed separately.',
    child: GlacierMobileSettingsForm(
      submitLabel: 'Save access',
      onSubmit: onSave,
      feedback: feedback,
      enabled: !readOnly && onSave != null,
      children: [
        GlacierMobileSelectField(
          label: 'Library role',
          value: role,
          options: const ['User', 'Viewer', 'Admin'],
          onChanged: readOnly ? null : onRoleChanged,
        ),
        GlacierMobilePermissionChoice(
          label: 'Library access enabled',
          detail:
              'Disable access without removing the person from this library.',
          selected: enabled,
          onChanged: readOnly ? null : onEnabledChanged,
        ),
        GlacierMobileSettingsSection(
          title: 'Explicit permissions',
          child: Column(
            children: [
              for (final permission in permissions)
                GlacierMobilePermissionChoice(
                  label: permission.label,
                  detail: permission.inherited
                      ? 'Included by the selected role'
                      : permission.detail,
                  selected: permission.selected,
                  onChanged: readOnly || permission.inherited
                      ? null
                      : (value) => onPermissionChanged(permission.id, value),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class GlacierMobileInvitation extends StatelessWidget {
  const GlacierMobileInvitation({
    super.key,
    required this.email,
    required this.status,
    this.code,
    this.onCopy,
    this.onRevoke,
    this.onInviteAgain,
  });
  final String email, status;
  final String? code;
  final VoidCallback? onCopy, onRevoke, onInviteAgain;
  @override
  Widget build(BuildContext context) => GlacierMobileSettingsSection(
    title: 'Invitations',
    first: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlacierMobileRecordRow(
          title: email,
          detail: status,
          icon: Icons.mail_outline,
        ),
        if (code != null)
          GlacierMobileSettingsSection(
            title: 'Share this invitation code',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlacierMobileSurface(
                  child: SelectableText(
                    code!,
                    style: const TextStyle(letterSpacing: .6),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only share this code with the intended recipient. They accept it from Libraries.',
                ),
                const SizedBox(height: 12),
                GlacierMobileActionBar(
                  children: [
                    GlacierButton(label: 'Copy code', onPressed: onCopy),
                    GlacierButton(
                      label: 'Revoke invitation',
                      onPressed: onRevoke,
                      kind: GlacierButtonKind.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (onInviteAgain != null)
          GlacierButton(label: 'Invite again', onPressed: onInviteAgain),
      ],
    ),
  );
}
