import 'package:flutter/material.dart';

import 'app_presenters.dart';
import 'app_ink_widgets.dart';
import 'glacier/glacier_controls.dart';

@immutable
final class AppAppearanceOption {
  const AppAppearanceOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

final class AppAppearanceMenu extends StatelessWidget {
  const AppAppearanceMenu({
    super.key,
    required this.selectedId,
    required this.options,
    required this.onSelected,
    required this.onClose,
    this.statusMessage,
    this.busy = false,
    this.onRetry,
  });

  final String selectedId;
  final List<AppAppearanceOption> options;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;
  final String? statusMessage;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppDialog(
    glacier: true,
    key: const Key('appearanceDialog'),
    title: 'Appearance',
    description: 'Choose how Domabas looks on this device.',
    width: 440,
    actions: [
      GlacierButton(
        key: const Key('closeAppearance'),
        onPressed: onClose,
        label: 'Done',
        kind: GlacierButtonKind.quiet,
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlacierChoice(
              key: Key('appearance-${option.id}'),
              label: option.label,
              description: option.id == 'system'
                  ? 'Follow your device settings'
                  : null,
              selected: selectedId == option.id,
              onChanged: (_) => onSelected(option.id),
            ),
          ),
        if (busy) const AppStripedProgressIndicator(),
        if (statusMessage case final message?) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(message, key: const Key('appearanceStatus')),
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: GlacierButton(
                key: const Key('retryAppearance'),
                onPressed: onRetry,
                label: 'Try again',
                icon: Icons.refresh,
                kind: GlacierButtonKind.quiet,
              ),
            ),
        ],
      ],
    ),
  );
}
