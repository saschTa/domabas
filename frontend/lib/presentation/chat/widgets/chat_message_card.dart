import 'package:flutter/material.dart';

import '../../../domain/chat/models/chat.dart';
import '../../../ui/domabas_ui.dart';

final class ChatMessageCard extends StatelessWidget {
  const ChatMessageCard({
    super.key,
    required this.message,
    this.onOpenDocument,
    this.onSendAgain,
  });
  final ChatMessage message;
  final Future<void> Function(String)? onOpenDocument;
  final VoidCallback? onSendAgain;
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: user ? scheme.surfaceContainerHigh : scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      user ? Icons.person_outline : Icons.auto_awesome_outlined,
                      size: 18,
                      color: scheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        user ? 'You' : 'Assistant',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (message.content.isNotEmpty)
                  SelectableText(
                    message.content,
                    key: ValueKey('chatMessage-${message.id}'),
                  ),
                if (!user && message.status != 'completed') ...[
                  if (message.content.isNotEmpty) const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (message.active) const AppJobSpinner(),
                        AppStatusBadge(
                          label: message.statusLabel,
                          tone: message.status == 'failed'
                              ? AppTone.danger
                              : message.status == 'cancelled' ||
                                    message.stage == 'waiting_for_ingestion'
                              ? AppTone.warning
                              : AppTone.info,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(message.statusDescription),
                  if (message.status == 'failed' ||
                      message.status == 'cancelled')
                    TextButton.icon(
                      key: ValueKey('sendAgain-${message.id}'),
                      onPressed: onSendAgain,
                      icon: const Icon(Icons.replay),
                      label: const Text('Send again'),
                    ),
                ],
                if (message.sources.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Documents consulted',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final source in message.sources)
                        Tooltip(
                          message: source.excerpt.isEmpty
                              ? source.title
                              : source.excerpt,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'chatSource-${message.id}-${source.documentId}',
                            ),
                            onPressed: onOpenDocument == null
                                ? null
                                : () => onOpenDocument!(source.documentId),
                            icon: const Icon(
                              Icons.description_outlined,
                              size: 18,
                            ),
                            label: Text(
                              source.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
