import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glacier_chat.dart';
import 'glacier_controls.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_theme.dart';

class GlacierMobileChatMessage extends StatelessWidget {
  const GlacierMobileChatMessage({
    super.key,
    required this.text,
    this.fromUser = false,
    this.sources = const [],
    this.author,
    this.textKey,
    this.trailing,
  });
  final String text;
  final bool fromUser;
  final List<GlacierChatSource> sources;
  final String? author;
  final Key? textKey;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    return Container(
      margin: EdgeInsets.only(left: fromUser ? 32 : 0, bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fromUser
            ? Theme.of(context).colorScheme.primaryContainer
            : tokens.surface,
        border: Border.all(color: tokens.edge),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            author ?? (fromUser ? 'You' : 'Domabas'),
            style: TextStyle(fontSize: 12, color: tokens.muted),
          ),
          const SizedBox(height: 7),
          if (textKey == null)
            Text(text, style: const TextStyle(fontSize: 15, height: 1.6))
          else
            SelectableText(
              text,
              key: textKey,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: trailing),
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton(
                key: source.key,
                onPressed: source.onOpen,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 21,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Documents consulted',
                            style: TextStyle(
                              fontSize: 12.75,
                              color: tokens.accent,
                            ),
                          ),
                          Text(
                            source.title,
                            style: TextStyle(
                              fontSize: 12.75,
                              color: tokens.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum GlacierMobileChatSubmitState { ready, sending, uncertain, disabled }

class GlacierMobileChatComposer extends StatelessWidget {
  const GlacierMobileChatComposer({
    super.key,
    required this.controller,
    this.state = GlacierMobileChatSubmitState.ready,
    this.onSend,
    this.onStop,
    this.onCheck,
    this.focusNode,
    this.onChanged,
    this.inputKey,
    this.sendKey,
    this.stopKey,
    this.checkKey,
    this.errorText,
    this.readOnly,
    this.minLines = 2,
    this.stopPending = false,
  });
  final TextEditingController controller;
  final GlacierMobileChatSubmitState state;
  final VoidCallback? onSend, onStop, onCheck;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final Key? inputKey, sendKey, stopKey, checkKey;
  final String? errorText;
  final bool? readOnly;
  final bool stopPending;
  final int minLines;

  bool get _canSend =>
      state == GlacierMobileChatSubmitState.ready &&
      controller.text.trim().isNotEmpty &&
      (!controller.value.composing.isValid ||
          controller.value.composing.isCollapsed);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileSurface(
        glass: true,
        radius: 16,
        padding: const EdgeInsets.all(8),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter &&
                (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed)) {
              if (_canSend) onSend?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final field = Semantics(
                label: 'Message',
                child: TextField(
                  key: inputKey,
                  controller: controller,
                  onChanged: onChanged,
                  focusNode: focusNode,
                  readOnly:
                      readOnly ?? state != GlacierMobileChatSubmitState.ready,
                  minLines: minLines,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                  decoration: InputDecoration(
                    errorText: errorText,
                    errorMaxLines: 3,
                    hintText: 'Ask about your documents…',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              );
              final action = ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => switch (state) {
                  GlacierMobileChatSubmitState.sending => GlacierButton(
                    key: stopKey,
                    label: stopPending ? 'Stopping…' : 'Stop',
                    onPressed: stopPending ? null : onStop,
                  ),
                  GlacierMobileChatSubmitState.uncertain => GlacierButton(
                    key: checkKey,
                    label: 'Check',
                    onPressed: onCheck,
                  ),
                  GlacierMobileChatSubmitState.disabled => GlacierButton(
                    key: sendKey,
                    label: 'Send',
                    onPressed: null,
                  ),
                  GlacierMobileChatSubmitState.ready => FilledButton(
                    key: sendKey,
                    onPressed: _canSend ? onSend : null,
                    child: Semantics(
                      label: 'Send message',
                      child: const Icon(Icons.send_outlined, size: 21),
                    ),
                  ),
                },
              );
              if (MediaQuery.textScalerOf(context).scale(15) > 22 ||
                  constraints.maxWidth < 250) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field,
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 8),
                  action,
                ],
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Enter adds a line · ⌘/Ctrl + Enter sends',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.25,
          color: GlacierTokens.of(context).muted,
        ),
      ),
    ],
  );
}

class GlacierMobileChatHistoryRow extends StatelessWidget {
  const GlacierMobileChatHistoryRow({
    super.key,
    required this.conversation,
    this.onOpen,
    this.onDelete,
  });
  final GlacierConversation conversation;
  final VoidCallback? onOpen, onDelete;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: GlacierMobileRecordRow(
          title: conversation.title,
          detail: conversation.updated,
          icon: Icons.chat_bubble_outline,
          onTap: onOpen,
        ),
      ),
      if (onDelete != null) ...[
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Delete ${conversation.title} conversation',
          color: Theme.of(context).colorScheme.error,
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: onDelete,
        ),
      ],
    ],
  );
}

class GlacierMobileChatHistory extends StatelessWidget {
  const GlacierMobileChatHistory({
    super.key,
    required this.conversations,
    this.onNew,
    this.onOpen,
    this.onDelete,
    this.onMore,
    this.onRetry,
    this.pageError = false,
  });
  final List<GlacierConversation> conversations;
  final VoidCallback? onNew, onMore, onRetry;
  final ValueChanged<String>? onOpen, onDelete;
  final bool pageError;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierButton(
        label: 'New conversation',
        onPressed: onNew,
        kind: GlacierButtonKind.primary,
      ),
      if (conversations.isEmpty)
        GlacierMobileNotice(
          title: 'No conversations yet',
          message: 'Start with a question about a document in this library.',
          attention: false,
          action: GlacierButton(label: 'New conversation', onPressed: onNew),
        )
      else ...[
        const SizedBox(height: 26),
        Text(
          'Your conversations',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 14),
        for (final conversation in conversations)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlacierMobileChatHistoryRow(
              conversation: conversation,
              onOpen: onOpen == null ? null : () => onOpen!(conversation.id),
              onDelete: onDelete == null
                  ? null
                  : () => onDelete!(conversation.id),
            ),
          ),
      ],
      if (pageError)
        GlacierMobileNotice(
          title: 'Older conversations could not load',
          message: 'Your current conversation and its draft are unchanged.',
          action: GlacierButton(label: 'Retry', onPressed: onRetry),
        ),
      if (onMore != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: GlacierButton(
            label: 'Load older conversations',
            onPressed: onMore,
          ),
        ),
    ],
  );
}

class GlacierMobileChatScreen extends StatelessWidget {
  const GlacierMobileChatScreen({
    super.key,
    required this.messages,
    this.onHistory,
    this.onNew,
    this.onEarlier,
    this.onSuggestion,
    this.notice,
    this.empty = false,
    this.composer,
  });
  final List<Widget> messages;
  final VoidCallback? onHistory, onNew, onEarlier, onSuggestion;
  final Widget? notice, composer;
  final bool empty;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileActionBar(
        glass: true,
        children: [
          GlacierButton(label: 'History', onPressed: onHistory),
          GlacierButton(label: 'New conversation', onPressed: onNew),
        ],
      ),
      ?notice,
      if (onEarlier != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: GlacierButton(
            label: 'Load earlier messages',
            onPressed: onEarlier,
          ),
        ),
      const SizedBox(height: 18),
      if (empty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
          child: Column(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: GlacierTokens.of(context).accent,
                size: 36,
              ),
              const SizedBox(height: 18),
              Text(
                'Ask about your documents',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Answers use documents in Personal library. Open the sources to check important details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: GlacierTokens.of(context).muted),
              ),
              const SizedBox(height: 18),
              GlacierButton(
                label: 'What is covered by my insurance?',
                onPressed: onSuggestion,
              ),
            ],
          ),
        )
      else
        ...messages,
      ?composer,
    ],
  );
}
