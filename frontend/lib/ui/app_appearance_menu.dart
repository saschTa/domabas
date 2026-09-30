import 'package:flutter/material.dart';

import 'app_presenters.dart';
import 'app_ink_widgets.dart';

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
    key: const Key('appearanceDialog'),
    title: 'Appearance',
    description: 'Choose how Domabas looks on this device.',
    width: 440,
    actions: [
      TextButton(
        key: const Key('closeAppearance'),
        onPressed: onClose,
        child: const Text('Done'),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              selected: selectedId == option.id,
              child: ListTile(
                key: Key('appearance-${option.id}'),
                minTileHeight: 56,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                selected: selectedId == option.id,
                selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer,
                leading: Icon(option.icon),
                title: Text(option.label),
                subtitle: option.id == 'system'
                    ? const Text('Follow your device settings')
                    : null,
                trailing: selectedId == option.id
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => onSelected(option.id),
              ),
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
              child: TextButton.icon(
                key: const Key('retryAppearance'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ),
        ],
      ],
    ),
  );
}
