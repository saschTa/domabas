import 'package:flutter/material.dart';

import '../app_presenters.dart';
import '../app_refreshable.dart';
import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';
import 'glacier_workspace_geometry.dart';
import 'glacier_interaction.dart';

final class GlacierSettingsSection extends StatelessWidget {
  const GlacierSettingsSection({
    super.key,
    this.title,
    this.description,
    this.trailing,
    required this.child,
    this.actions = const [],
  });
  final String? title, description;
  final Widget? trailing;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => GlacierSurface(
    surface: true,
    blur: false,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || trailing != null) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (title != null)
                Semantics(
                  header: true,
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ?trailing,
            ],
          ),
          SizedBox(height: description == null ? 20 : 8),
        ],
        if (description != null) ...[
          Text(
            description!,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: GlacierTokens.of(context).muted),
          ),
          const SizedBox(height: 20),
        ],
        child,
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 8, children: actions),
        ],
      ],
    ),
  );
}

final class GlacierSettingsHeader extends StatelessWidget {
  const GlacierSettingsHeader({
    super.key,
    required this.parentLabel,
    required this.title,
    required this.onBack,
  });
  final String parentLabel, title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      GlacierButton(
        label: parentLabel,
        icon: Icons.arrow_back,
        onPressed: onBack,
      ),
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );
}

@immutable
final class GlacierSettingsDestination {
  const GlacierSettingsDestination({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    this.key,
  });
  final String id, label, description;
  final IconData icon;
  final Key? key;
}

final class GlacierSettingsOverview extends StatelessWidget {
  const GlacierSettingsOverview({
    super.key,
    required this.destinations,
    required this.onSelected,
    this.header,
  });
  final List<GlacierSettingsDestination> destinations;
  final ValueChanged<String> onSelected;
  final Widget? header;

  @override
  Widget build(BuildContext context) => GlacierSettingsPage(
    header: header,
    sections: [
      for (final destination in destinations)
        glacierInteractionOutline(
          radius: 16,
          builder: (states, hovered) => GlacierSurface(
            padding: EdgeInsets.zero,
            surface: true,
            blur: false,
            borderColor: hovered ? GlacierTokens.of(context).accent : null,
            child: InkWell(
              key: destination.key,
              statesController: states,
              focusColor: Colors.transparent,
              onTap: () => onSelected(destination.id),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      destination.icon,
                      size: 22,
                      color: GlacierTokens.of(context).muted,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destination.label,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            destination.description,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: GlacierTokens.of(context).muted,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: GlacierTokens.of(context).muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

final class GlacierSettingsPage extends StatelessWidget {
  const GlacierSettingsPage({
    super.key,
    required this.sections,
    this.feedback,
    this.header,
    this.actions = const [],
    this.onRefresh,
    this.scrollController,
  });
  final List<Widget> sections;
  final Widget? feedback;
  final Widget? header;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final ScrollController? scrollController;

  static EdgeInsets scrollPadding(
    BuildContext context, {
    double top = 24,
    double bottom = 24,
  }) {
    final horizontal = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 20.0;
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottom +
          GlacierWorkspaceGeometry.trailingOf(context, existingBottom: bottom),
    );
  }

  Widget _actionBar() => GlacierSurface(
    radius: 13,
    child: Wrap(spacing: 12, runSpacing: 8, children: actions),
  );
  @override
  Widget build(BuildContext context) {
    final scoped = GlacierWorkspaceGeometry.maybeOf(context) != null;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (feedback != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: feedback,
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 20,
              24,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 20,
              24,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (header != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: header,
                      ),
                    for (var index = 0; index < sections.length; index++)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
                        child: sections[index],
                      ),
                    if (scoped && actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: GlacierWorkspaceGeometry.measureEndActions(
                          context,
                          followingExtent: 24,
                          child: _actionBar(),
                        ),
                      ),
                    if (scoped)
                      SizedBox(
                        height: GlacierWorkspaceGeometry.trailingOf(
                          context,
                          existingBottom: 24,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!scoped && actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: _actionBar(),
              ),
            ),
          ),
      ],
    );
    return onRefresh == null
        ? body
        : AppRefreshable(onRefresh: onRefresh, child: body);
  }
}

final class GlacierFieldGrid extends StatelessWidget {
  const GlacierFieldGrid({
    super.key,
    required this.children,
    this.minimumWidth = 280,
  });
  final List<Widget> children;
  final double minimumWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= minimumWidth * 2 + 20 ? 2 : 1;
      final fieldWidth = (width - (columns - 1) * 20) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (final child in children)
            SizedBox(width: fieldWidth, child: child),
        ],
      );
    },
  );
}

final class GlacierSettingsRecord extends StatelessWidget {
  const GlacierSettingsRecord({
    super.key,
    required this.title,
    required this.detail,
    this.icon,
    this.status,
    this.actions = const [],
    this.onTap,
    this.card = false,
  });
  final String title, detail;
  final IconData? icon;
  final Widget? status;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final record = Container(
      padding: card
          ? const EdgeInsets.all(20)
          : const EdgeInsets.symmetric(vertical: 20),
      decoration: card
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GlacierTokens.of(context).border),
              ),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 14),
                  child: Icon(icon, size: 22),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall),
                    if (status != null && constraints.maxWidth < 560)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: status,
                      ),
                  ],
                ),
              ),
            ],
          );
          final controls = Wrap(spacing: 8, runSpacing: 8, children: actions);
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                if (actions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 12,
                      left: icon == null ? 0 : 36,
                    ),
                    child: controls,
                  ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              if (status != null || actions.isNotEmpty) ...[
                const SizedBox(width: 18),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .55,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 18,
                    runSpacing: 8,
                    children: [?status, ...actions],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
    Widget surface(Widget child, {bool hovered = false}) => card
        ? GlacierSurface(
            padding: EdgeInsets.zero,
            surface: true,
            blur: false,
            borderColor: hovered ? GlacierTokens.of(context).accent : null,
            child: child,
          )
        : child;
    return onTap == null
        ? surface(record)
        : glacierInteractionOutline(
            radius: card ? 16 : 10,
            builder: (states, hovered) => surface(
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  statesController: states,
                  onTap: onTap,
                  focusColor: Colors.transparent,
                  child: record,
                ),
              ),
              hovered: hovered,
            ),
          );
  }
}

final class GlacierIdentityContext extends StatelessWidget {
  const GlacierIdentityContext({
    super.key,
    required this.name,
    required this.email,
    required this.scope,
  });
  final String name, email, scope;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(bottom: 20),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: GlacierTokens.of(context).border),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(email),
        const SizedBox(height: 6),
        Text(scope, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

@immutable
final class GlacierPermission {
  const GlacierPermission({
    required this.id,
    required this.label,
    this.description = '',
    this.selected = false,
    this.inherited = false,
  });
  final String id, label, description;
  final bool selected, inherited;
}

final class GlacierPermissionGroup extends StatelessWidget {
  const GlacierPermissionGroup({
    super.key,
    required this.title,
    required this.permissions,
    this.onChanged,
    this.enabled = true,
  });
  final String title;
  final List<GlacierPermission> permissions;
  final void Function(String id, bool selected)? onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => GlacierSection(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final permission in permissions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlacierChoice(
              label: permission.label,
              description: permission.inherited
                  ? 'Included in this role'
                  : permission.description,
              selected: permission.selected || permission.inherited,
              onChanged: enabled && !permission.inherited && onChanged != null
                  ? (value) => onChanged!(permission.id, value ?? false)
                  : null,
            ),
          ),
      ],
    ),
  );
}

final class GlacierMemberEditor extends StatelessWidget {
  const GlacierMemberEditor({
    super.key,
    required this.identity,
    required this.roleField,
    required this.permissionGroups,
    required this.accessControl,
    this.notice,
  });
  final Widget identity, roleField, accessControl;
  final List<Widget> permissionGroups;
  final Widget? notice;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      identity,
      roleField,
      const SizedBox(height: 20),
      if (notice != null) ...[notice!, const SizedBox(height: 20)],
      for (final group in permissionGroups)
        Padding(padding: const EdgeInsets.only(bottom: 24), child: group),
      accessControl,
    ],
  );
}

final class GlacierInvitationCode extends StatelessWidget {
  const GlacierInvitationCode({
    super.key,
    required this.email,
    required this.library,
    required this.code,
    required this.expires,
    this.onCopy,
    this.copyFeedback,
  });
  final String email, library, code, expires;
  final VoidCallback? onCopy;
  final String? copyFeedback;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Share with $email'),
      const SizedBox(height: 6),
      Text(library),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(
          code,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Expires $expires. Only the intended signed-in person can accept this code.',
      ),
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerLeft,
        child: GlacierButton(
          label: 'Copy code',
          icon: Icons.copy_outlined,
          onPressed: onCopy,
        ),
      ),
      if (copyFeedback != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(copyFeedback!, semanticsLabel: copyFeedback),
        ),
    ],
  );
}

final class GlacierCredentialField extends StatelessWidget {
  const GlacierCredentialField({
    super.key,
    required this.label,
    required this.controller,
    required this.configured,
    required this.removeStored,
    this.onRemoveChanged,
    this.onChanged,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final bool configured, removeStored, enabled;
  final ValueChanged<bool>? onRemoveChanged;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierField(
        label: label,
        controller: controller,
        obscureText: true,
        enabled: enabled && !removeStored,
        onChanged: onChanged,
        helper: configured
            ? 'Leave empty to keep the stored credential.'
            : 'No credential is currently stored.',
      ),
      if (configured) ...[
        const SizedBox(height: 12),
        GlacierChoice(
          label: 'Remove stored credential',
          description: 'The saved key will be removed when you save.',
          selected: removeStored,
          onChanged: enabled && onRemoveChanged != null
              ? (value) => onRemoveChanged!(value ?? false)
              : null,
        ),
      ],
    ],
  );
}

final class GlacierAuthPanel extends StatelessWidget {
  const GlacierAuthPanel({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.description,
    this.feedback,
    this.secondaryActions = const [],
    this.footer,
  });
  final String title;
  final String? description;
  final List<Widget> fields, secondaryActions;
  final Widget submit;
  final Widget? feedback, footer;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlacierSurface(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (description != null) ...[
                const SizedBox(height: 12),
                Text(description!),
              ],
              const SizedBox(height: 28),
              if (feedback != null) ...[feedback!, const SizedBox(height: 20)],
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: field,
                ),
              submit,
              if (secondaryActions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8, children: secondaryActions),
              ],
              if (footer != null) ...[const SizedBox(height: 20), footer!],
            ],
          ),
        ),
      ),
    ),
  );
}

final class GlacierRecoveryPanel extends StatelessWidget {
  const GlacierRecoveryPanel({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    this.busy = false,
    this.icon = Icons.sync_problem_outlined,
  });
  final String title, message;
  final List<Widget> actions;
  final bool busy;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlacierSurface(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(message),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: AppProgressSlot(active: true),
                ),
              const SizedBox(height: 24),
              Wrap(spacing: 12, runSpacing: 8, children: actions),
            ],
          ),
        ),
      ),
    ),
  );
}

final class GlacierPasswordFields extends StatelessWidget {
  const GlacierPasswordFields({
    super.key,
    required this.current,
    required this.password,
    required this.confirmation,
    this.onChanged,
    this.error,
    this.enabled = true,
  });
  final TextEditingController current, password, confirmation;
  final ValueChanged<String>? onChanged;
  final String? error;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Changing your password signs you out on all devices.'),
      const SizedBox(height: 20),
      GlacierField(
        label: 'Current password',
        controller: current,
        obscureText: true,
        enabled: enabled,
        onChanged: onChanged,
      ),
      const SizedBox(height: 20),
      GlacierField(
        label: 'New password',
        controller: password,
        obscureText: true,
        enabled: enabled,
        helper: 'Use 8–128 characters.',
        onChanged: onChanged,
      ),
      const SizedBox(height: 20),
      GlacierField(
        label: 'Confirm new password',
        controller: confirmation,
        obscureText: true,
        enabled: enabled,
        error: error,
        onChanged: onChanged,
      ),
    ],
  );
}

final class GlacierServerForm extends StatelessWidget {
  const GlacierServerForm({
    super.key,
    required this.address,
    required this.onConnect,
    this.onReload,
    this.error,
    this.busy = false,
    this.hosted = false,
  });
  final TextEditingController address;
  final VoidCallback? onConnect, onReload;
  final String? error;
  final bool busy, hosted;
  @override
  Widget build(BuildContext context) => GlacierSection(
    title: hosted ? 'Hosted server' : 'Connect to your server',
    description: hosted
        ? 'The browser uses the address that serves Domabas.'
        : 'Connecting replaces the current account and library workspace.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlacierField(
          label: 'Server address',
          controller: address,
          error: error,
          enabled: !hosted && !busy,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (!hosted)
              GlacierButton(
                label: 'Connect',
                kind: GlacierButtonKind.primary,
                onPressed: busy ? null : onConnect,
                busy: busy,
              ),
            if (!hosted)
              GlacierButton(
                label: 'Reload saved server',
                onPressed: busy ? null : onReload,
              ),
          ],
        ),
      ],
    ),
  );
}

@immutable
final class GlacierAppearanceValue {
  const GlacierAppearanceValue({
    this.mode = 'system',
    this.background = 'activity',
    this.pattern = 'line',
    this.softness = 35,
    this.reduceTransparency = false,
  });
  final String mode, background, pattern;
  final double softness;
  final bool reduceTransparency;
}

final class GlacierAppearancePreferences extends StatelessWidget {
  const GlacierAppearancePreferences({
    super.key,
    required this.value,
    required this.onModeChanged,
    required this.onBackgroundChanged,
    required this.onPatternChanged,
    required this.onSoftnessChanged,
    required this.onTransparencyChanged,
    this.status,
    this.onRetry,
    this.footer,
  });
  final GlacierAppearanceValue value;
  final ValueChanged<String> onModeChanged,
      onBackgroundChanged,
      onPatternChanged;
  final ValueChanged<double> onSoftnessChanged;
  final ValueChanged<bool> onTransparencyChanged;
  final String? status;
  final VoidCallback? onRetry;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = GlacierTokens.of(context);
    Widget select(
      String label,
      String selected,
      Map<String, String> options,
      ValueChanged<String> changed,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          style: theme.textTheme.bodyMedium,
          decoration: const InputDecoration(),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (next) {
            if (next != null) changed(next);
          },
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choose the appearance and atmosphere of your workspace.'),
        const SizedBox(height: 24),
        select('Glacier appearance', value.mode, const {
          'system': 'System',
          'light': 'Light',
          'dark': 'Dark',
        }, onModeChanged),
        const SizedBox(height: 16),
        Text(
          'Light and dark share the same layout. System follows your device. Original documents keep their own colors.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 420 ? 1 : 3;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in const [
                  ('atmosphere', 'Atmosphere', 'Soft color & light'),
                  ('activity', 'Activity', 'Abstract line or grid'),
                  ('plain', 'Plain', 'A quiet solid canvas'),
                ])
                  SizedBox(
                    width: width,
                    child: glacierInteractionOutline(
                      radius: 12,
                      focusOffset: 2,
                      builder: (states, _) => Semantics(
                        selected: value.background == entry.$1,
                        button: true,
                        child: Material(
                          color: theme.colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: value.background == entry.$1
                                  ? tokens.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            statesController: states,
                            focusColor: Colors.transparent,
                            onTap: () => onBackgroundChanged(entry.$1),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    height: 64,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      color: tokens.canvas,
                                      gradient: entry.$1 == 'plain'
                                          ? null
                                          : LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors:
                                                  theme.brightness ==
                                                      Brightness.dark
                                                  ? const [
                                                      Color(0xFF22575E),
                                                      Color(0xFF172C35),
                                                      Color(0xFF364768),
                                                    ]
                                                  : const [
                                                      Color(0xFFA6D5CF),
                                                      Color(0xFFD9E7E9),
                                                      Color(0xFFCCC5E4),
                                                    ],
                                              stops: entry.$1 == 'activity'
                                                  ? const [.12, .52, .75]
                                                  : null,
                                            ),
                                    ),
                                    child: entry.$1 == 'activity'
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                            child: CustomPaint(
                                              painter:
                                                  _GlacierActivityPreviewPainter(
                                                    color: tokens.accent,
                                                    grid:
                                                        value.pattern == 'grid',
                                                  ),
                                              child: const SizedBox.expand(),
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    entry.$2,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.$3,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (value.background == 'activity') ...[
          const SizedBox(height: 24),
          GlacierFieldGrid(
            minimumWidth: 220,
            children: [
              select('Background pattern', value.pattern, const {
                'line': 'Line',
                'grid': 'Day grid',
              }, onPatternChanged),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Softness', style: theme.textTheme.bodySmall),
                      Text(
                        '${value.softness.round()}%',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Slider(
                    value: value.softness,
                    min: 0,
                    max: 100,
                    label: '${value.softness.round()}%',
                    onChanged: value.reduceTransparency
                        ? null
                        : onSoftnessChanged,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Distinct', style: theme.textTheme.bodySmall),
                      Text('Soft', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'An abstract, blurred background. The activity pattern belongs behind your workspace.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Transform.scale(
              scale: .8,
              alignment: Alignment.centerLeft,
              child: Switch(
                value: value.reduceTransparency,
                onChanged: onTransparencyChanged,
              ),
            ),
            const SizedBox(width: 4),
            const Expanded(child: Text('Reduce transparency')),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'More opaque surfaces keep text stable over any backdrop.',
          style: theme.textTheme.bodySmall,
        ),
        if (footer != null) ...[const SizedBox(height: 24), footer!],
        if (status != null) ...[
          const SizedBox(height: 20),
          AppNotice(
            message: status!,
            action: onRetry == null
                ? null
                : GlacierButton(label: 'Try again', onPressed: onRetry),
          ),
        ],
      ],
    );
  }
}

final class _GlacierActivityPreviewPainter extends CustomPainter {
  const _GlacierActivityPreviewPainter({
    required this.color,
    required this.grid,
  });
  final Color color;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    const values = [.25, .45, .35, .65, .5, .82, .7, .9];
    if (grid) {
      final cellWidth = (size.width - 30) / 8;
      for (var column = 0; column < 8; column++) {
        for (var row = 0; row < 3; row++) {
          final intensity = values[(column + row * 3) % values.length];
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                10 + column * (cellWidth + 1),
                10 + row * 15,
                cellWidth - 2,
                11,
              ),
              const Radius.circular(2),
            ),
            Paint()..color = color.withValues(alpha: .2 + intensity * .6),
          );
        }
      }
      return;
    }
    final line = Path();
    for (var index = 0; index < values.length; index++) {
      final x = 10 + (size.width - 20) * index / (values.length - 1);
      final y = size.height - 10 - values[index] * (size.height - 20);
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final area = Path.from(line)
      ..lineTo(size.width - 10, size.height - 8)
      ..lineTo(10, size.height - 8)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .15));
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GlacierActivityPreviewPainter oldDelegate) =>
      color != oldDelegate.color || grid != oldDelegate.grid;
}

final class GlacierModelConnection extends StatelessWidget {
  const GlacierModelConnection({
    super.key,
    required this.modelField,
    required this.credentialField,
    required this.endpointField,
    this.compatibilityControl,
  });

  final Widget modelField, credentialField, endpointField;
  final Widget? compatibilityControl;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierFieldGrid(children: [endpointField, modelField]),
      const SizedBox(height: 20),
      const AppNotice(
        message: 'Selected document content is sent to your OpenAI-compatible service.',
        tone: AppTone.warning,
      ),
      credentialField,
      if (compatibilityControl != null) ...[
        const SizedBox(height: 20),
        compatibilityControl!,
      ],
    ],
  );
}

final class GlacierEmailAccountForm extends StatelessWidget {
  const GlacierEmailAccountForm({
    super.key,
    required this.connectionFields,
    required this.scheduleFields,
    required this.credentialField,
    required this.enabledControl,
    required this.consentControl,
    this.feedback,
    this.testActions = const [],
  });
  final List<Widget> connectionFields, scheduleFields, testActions;
  final Widget credentialField, enabledControl, consentControl;
  final Widget? feedback;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierSection(
        title: 'Mailbox connection',
        description: 'IMAP uses implicit TLS. Imported mail and supported attachments stay in this library.',
        child: Column(
          children: [
            GlacierFieldGrid(children: connectionFields),
            const SizedBox(height: 20),
            credentialField,
          ],
        ),
      ),
      const SizedBox(height: 28),
      GlacierSection(
        title: 'Automatic import',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlacierFieldGrid(children: scheduleFields),
            const SizedBox(height: 20),
            enabledControl,
            const SizedBox(height: 12),
            consentControl,
          ],
        ),
      ),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 8, children: testActions),
      if (feedback != null) ...[const SizedBox(height: 16), feedback!],
    ],
  );
}

final class GlacierWorkloadResource extends StatelessWidget {
  const GlacierWorkloadResource({
    super.key,
    required this.label,
    required this.limitField,
    required this.active,
    required this.savedLimit,
    required this.maximumLimit,
    this.description,
    this.notice,
  });
  final String label;
  final Widget limitField;
  final int active, savedLimit, maximumLimit;
  final String? description, notice;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(label, style: text.titleMedium)),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: text.bodySmall?.copyWith(
              color: GlacierTokens.of(context).muted,
            ),
          ),
        ],
      ],
    );
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        limitField,
        const SizedBox(height: 4),
        Text('Allowed: 1–$maximumLimit', style: text.bodySmall),
      ],
    );
    final meter = GlacierCapacityMeter(active: active, limit: savedLimit);
    return GlacierSurface(
      surface: true,
      blur: false,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >=
              600 * MediaQuery.textScalerOf(context).scale(1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  children: [
                    Expanded(flex: 3, child: summary),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: meter),
                    const SizedBox(width: 24),
                    SizedBox(width: 150, child: editor),
                  ],
                )
              else ...[
                summary,
                const SizedBox(height: 12),
                meter,
                const SizedBox(height: 16),
                editor,
              ],
              if (notice != null) ...[
                const SizedBox(height: 8),
                Text(notice!, style: text.bodySmall),
              ],
            ],
          );
        },
      ),
    );
  }
}

final class GlacierCapacityMeter extends StatelessWidget {
  const GlacierCapacityMeter({
    super.key,
    required this.active,
    required this.limit,
  });

  final int active, limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = active >= limit;
    final usage = '$active of $limit in use';
    return Semantics(
      label: usage,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text(usage, style: theme.textTheme.labelLarge),
                if (full)
                  Text(
                    active > limit ? 'Draining' : 'At capacity',
                    style: theme.textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(
                end: limit > 0 ? (active / limit).clamp(0.0, 1.0) : 0.0,
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                color: full
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class GlacierLicenseReader extends StatelessWidget {
  const GlacierLicenseReader({
    super.key,
    required this.name,
    required this.version,
    required this.text,
  });
  final String name, version, text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(version),
      const SizedBox(height: 24),
      SelectableText(text),
    ],
  );
}

final class GlacierAccountMenu extends StatelessWidget {
  const GlacierAccountMenu({
    super.key,
    required this.identity,
    required this.actions,
  });
  final Widget identity;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      identity,
      for (final action in actions)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
    ],
  );
}
