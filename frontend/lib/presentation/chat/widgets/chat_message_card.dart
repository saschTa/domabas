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
    final incomplete = !user && message.status != 'completed';
    final sources = [
      for (final source in message.sources)
        GlacierChatSource(
          key: ValueKey('chatSource-${message.id}-${source.documentId}'),
          title: source.title,
          excerpt: source.excerpt.isEmpty ? null : source.excerpt,
          onOpen: onOpenDocument == null
              ? null
              : () => onOpenDocument!(source.documentId),
        ),
    ];
    if (MediaQuery.sizeOf(context).width < 800) {
      return GlacierMobileChatMessage(
        text: message.content,
        textKey: ValueKey('chatMessage-${message.id}'),
        fromUser: user,
        sources: sources,
        trailing: !incomplete
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Wrap(
                      spacing: 8,
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
                    GlacierButton(
                      key: ValueKey('sendAgain-${message.id}'),
                      label: 'Send again',
                      icon: Icons.replay,
                      kind: GlacierButtonKind.quiet,
                      onPressed: onSendAgain,
                    ),
                ],
              ),
      );
    }
    return GlacierChatMessage(
      text: message.content,
      textKey: ValueKey('chatMessage-${message.id}'),
      fromUser: user,
      status: incomplete ? message.statusLabel : null,
      statusDescription: incomplete ? message.statusDescription : null,
      active: message.active,
      failed: message.status == 'failed',
      statusTone: message.status == 'failed'
          ? AppTone.danger
          : message.status == 'cancelled' ||
                message.stage == 'waiting_for_ingestion'
          ? AppTone.warning
          : AppTone.info,
      showRetry:
          incomplete &&
          (message.status == 'failed' || message.status == 'cancelled'),
      retryKey: ValueKey('sendAgain-${message.id}'),
      onSendAgain:
          incomplete &&
              (message.status == 'failed' || message.status == 'cancelled')
          ? onSendAgain
          : null,
      sources: sources,
    );
  }
}
